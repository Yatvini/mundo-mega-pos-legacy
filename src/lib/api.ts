import { supabase } from './supabase'

const db = () => {
  if (!supabase) throw new Error('Supabase no está configurado. Agrega las variables VITE_SUPABASE_* en .env.')
  return supabase
}

export const api = {
  auth: {
    signIn: (email: string, password: string) => db().auth.signInWithPassword({ email, password }),
    signOut: () => db().auth.signOut(),
    session: () => db().auth.getSession(),
  },
  products: {
    list: async (branchId: string) => db().from('products').select('*, categories(name), inventory!inner(stock, branch_id)').eq('inventory.branch_id', branchId).eq('active', true).order('name'),
    save: async (product: Record<string, unknown>) => db().from('products').upsert(product).select().single(),
    archive: async (id: string) => db().from('products').update({ active: false }).eq('id', id),
  },
  customers: {
    list: async () => db().from('customers').select('*').eq('active', true).order('name'),
    save: async (customer: Record<string, unknown>) => db().from('customers').upsert(customer).select().single(),
  },
  suppliers: {
    list: async () => db().from('suppliers').select('*').eq('active', true).order('name'),
  },
  sales: {
    recent: async (branchId: string) => db().from('sales').select('*, customers(name), profiles(full_name), sale_items(quantity), sale_payments(method,amount)').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(50),
    async checkout(input: {
      businessId: string; branchId: string; sessionId?: string; cashierId: string;
      customerId?: string; items: Array<{ product_id: string; product_name: string; quantity: number; unit_cost: number; unit_price: number; discount: number; tax: number; total: number }>;
      payments: Array<{ method: 'cash'|'card'|'transfer'|'credit'; amount: number; reference?: string }>;
    }) {
      let sessionId = input.sessionId
      if (!sessionId) {
        const { data: openSession } = await db().from('cash_sessions').select('id').eq('branch_id', input.branchId).is('closed_at', null).order('opened_at', { ascending: false }).limit(1).maybeSingle()
        sessionId = openSession?.id
      }
      const subtotal = input.items.reduce((sum, item) => sum + item.unit_price * item.quantity, 0)
      const discount = input.items.reduce((sum, item) => sum + item.discount, 0)
      const tax = input.items.reduce((sum, item) => sum + item.tax, 0)
      const { data: sale, error } = await db().from('sales').insert({
        business_id: input.businessId, branch_id: input.branchId, session_id: sessionId || null,
        cashier_id: input.cashierId, customer_id: input.customerId, subtotal, discount, tax,
        total: subtotal - discount + tax,
      }).select().single()
      if (error) throw error
      const { error: itemsError } = await db().from('sale_items').insert(input.items.map(item => ({ ...item, sale_id: sale.id })))
      if (itemsError) { await db().from('sales').delete().eq('id', sale.id); throw itemsError }
      const { error: checkoutError } = await db().rpc('complete_sale', { p_sale_id: sale.id, p_payments: input.payments })
      if (checkoutError) throw checkoutError
      return sale
    },
  },
  cash: {
    open: async (branchId: string, userId: string, openingAmount: number) => db().from('cash_sessions').insert({ branch_id: branchId, user_id: userId, opening_amount: openingAmount }).select().single(),
    movement: async (sessionId: string, userId: string, kind: 'income'|'expense', amount: number, description: string) => db().from('cash_movements').insert({ session_id: sessionId, user_id: userId, kind, amount, description }).select().single(),
    close: async (sessionId: string, closingAmount: number, expectedAmount: number, notes?: string) => db().from('cash_sessions').update({ closed_at: new Date().toISOString(), closing_amount: closingAmount, expected_amount: expectedAmount, notes }).eq('id', sessionId).select().single(),
  },
  reports: {
    sales: async (branchId: string, from: string, to: string) => db().from('sales').select('id,total,tax,discount,created_at,sale_items(quantity,unit_cost,unit_price,product_name)').eq('branch_id', branchId).eq('status', 'completed').gte('created_at', from).lte('created_at', to),
  },
}
