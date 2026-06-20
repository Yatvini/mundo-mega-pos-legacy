import { supabase } from './supabase'
import type { Product } from '../types'

export type StoreProfile = {
  id: string
  businessId: string
  branchId: string
  fullName: string
  role: string
  businessName: string
  branchName: string
}
export type Customer = { id:string; name:string; phone:string; email:string; taxId:string; points:number; createdAt:string }
export type Purchase = { id:string; supplier:string; invoice:string; date:string; total:number; paymentStatus:string }
export type CashData = { session:null|{id:string;openedAt:string;openingAmount:number}; movements:Array<{id:string;kind:string;amount:number;description:string;createdAt:string}>; payments:Array<{method:string;amount:number}> }
export type LiveSale = { id:string; number:number; date:string; total:number; subtotal:number; status:string; customer:string; cashier:string; items:number; method:string; cost:number }

export async function loadStore() {
  if (!supabase) throw new Error('Supabase no está configurado')
  const { data: auth } = await supabase.auth.getUser()
  if (!auth.user) throw new Error('Sesión no encontrada')
  const { data: row, error: profileError } = await supabase
    .from('profiles')
    .select('id,business_id,branch_id,full_name,role,businesses(name),branches(name)')
    .eq('id', auth.user.id).single()
  if (profileError) throw profileError
  const profile: StoreProfile = {
    id: row.id, businessId: row.business_id, branchId: row.branch_id,
    fullName: row.full_name, role: row.role,
    businessName: (row.businesses as any)?.name ?? 'Mi minimarket',
    branchName: (row.branches as any)?.name ?? 'Sucursal Central',
  }
  const { data: rows, error: productError } = await supabase
    .from('products')
    .select('id,name,sku,barcode,unit,cost,price,min_stock,categories(name),inventory(stock,branch_id)')
    .eq('business_id', profile.businessId).eq('active', true).order('name')
  if (productError) throw productError
  const products: Product[] = (rows ?? []).map((p: any) => {
    const inventory = (p.inventory ?? []).find((i: any) => i.branch_id === profile.branchId)
    return { id:p.id,name:p.name,sku:p.sku,barcode:p.barcode??'',category:p.categories?.name??'Sin categoría',price:Number(p.price),cost:Number(p.cost),stock:Number(inventory?.stock??0),minStock:Number(p.min_stock),unit:p.unit,emoji:'📦',color:'#3a9766' }
  })
  return { profile, products }
}

export async function createProduct(profile: StoreProfile, input: {name:string;sku:string;barcode:string;category:string;unit:string;cost:number;price:number;stock:number;minStock:number}) {
  if (!supabase) throw new Error('Supabase no está configurado')
  let categoryId: string | null = null
  if (input.category.trim()) {
    const { data: existing } = await supabase.from('categories').select('id').eq('business_id',profile.businessId).ilike('name',input.category.trim()).maybeSingle()
    if (existing) categoryId=existing.id
    else { const {data,error}=await supabase.from('categories').insert({business_id:profile.businessId,name:input.category.trim()}).select('id').single();if(error)throw error;categoryId=data.id }
  }
  const {data: product,error}=await supabase.from('products').insert({business_id:profile.businessId,category_id:categoryId,name:input.name,sku:input.sku,barcode:input.barcode||null,unit:input.unit,cost:input.cost,price:input.price,min_stock:input.minStock}).select('id').single()
  if(error)throw error
  const {error:inventoryError}=await supabase.from('inventory').insert({branch_id:profile.branchId,product_id:product.id,stock:input.stock})
  if(inventoryError)throw inventoryError
  return product.id
}

export async function loadCustomers(profile: StoreProfile) {
  if (!supabase) throw new Error('Supabase no está configurado')
  const {data,error}=await supabase.from('customers').select('id,name,phone,email,tax_id,points,created_at').eq('business_id',profile.businessId).eq('active',true).order('name')
  if(error)throw error
  return (data??[]).map(c=>({id:c.id,name:c.name,phone:c.phone??'',email:c.email??'',taxId:c.tax_id??'',points:c.points,createdAt:c.created_at})) as Customer[]
}

export async function createCustomer(profile: StoreProfile, input: {name:string;phone:string;email:string;taxId:string}) {
  if (!supabase) throw new Error('Supabase no está configurado')
  const {error}=await supabase.from('customers').insert({business_id:profile.businessId,name:input.name,phone:input.phone||null,email:input.email||null,tax_id:input.taxId||null})
  if(error)throw error
}

export async function loadPurchases(profile: StoreProfile) {
  if (!supabase) throw new Error('Supabase no está configurado')
  const {data,error}=await supabase.from('purchases').select('id,invoice_number,purchased_at,total,payment_status,suppliers(name)').eq('business_id',profile.businessId).order('purchased_at',{ascending:false}).limit(50)
  if(error)throw error
  return (data??[]).map((p:any)=>({id:p.id,supplier:p.suppliers?.name??'Sin proveedor',invoice:p.invoice_number??'—',date:p.purchased_at,total:Number(p.total),paymentStatus:p.payment_status})) as Purchase[]
}

export async function receivePurchase(profile: StoreProfile,input:{supplier:string;invoice:string;paymentStatus:string;productId:string;quantity:number;unitCost:number}) {
  if (!supabase) throw new Error('Supabase no está configurado')
  const {error}=await supabase.rpc('receive_purchase',{p_branch_id:profile.branchId,p_supplier_name:input.supplier,p_invoice_number:input.invoice,p_payment_status:input.paymentStatus,p_items:[{product_id:input.productId,quantity:input.quantity,unit_cost:input.unitCost}]})
  if(error)throw error
}

export async function loadCash(profile: StoreProfile): Promise<CashData> {
  if (!supabase) throw new Error('Supabase no está configurado')
  const {data:session,error}=await supabase.from('cash_sessions').select('id,opened_at,opening_amount').eq('branch_id',profile.branchId).is('closed_at',null).order('opened_at',{ascending:false}).limit(1).maybeSingle()
  if(error)throw error
  if(!session)return {session:null,movements:[],payments:[]}
  const [{data:movements,error:me},{data:payments,error:pe}]=await Promise.all([
    supabase.from('cash_movements').select('id,kind,amount,description,created_at').eq('session_id',session.id).order('created_at',{ascending:false}),
    supabase.from('sale_payments').select('method,amount,sales!inner(session_id,status)').eq('sales.session_id',session.id).eq('sales.status','completed')
  ])
  if(me)throw me;if(pe)throw pe
  return {session:{id:session.id,openedAt:session.opened_at,openingAmount:Number(session.opening_amount)},movements:(movements??[]).map(m=>({id:m.id,kind:m.kind,amount:Number(m.amount),description:m.description,createdAt:m.created_at})),payments:(payments??[]).map(p=>({method:p.method,amount:Number(p.amount)}))}
}

export async function openCash(profile:StoreProfile,amount:number){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_sessions').insert({branch_id:profile.branchId,user_id:profile.id,opening_amount:amount});if(error)throw error}
export async function addCashMovement(profile:StoreProfile,sessionId:string,kind:'income'|'expense',amount:number,description:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_movements').insert({session_id:sessionId,user_id:profile.id,kind,amount,description});if(error)throw error}
export async function closeCash(sessionId:string,closingAmount:number,expectedAmount:number){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_sessions').update({closed_at:new Date().toISOString(),closing_amount:closingAmount,expected_amount:expectedAmount}).eq('id',sessionId);if(error)throw error}

export async function loadSales(profile:StoreProfile,limit=100):Promise<LiveSale[]>{
  if(!supabase)throw new Error('Supabase no está configurado')
  const {data,error}=await supabase.from('sales').select('id,number,created_at,total,subtotal,status,customers(name),profiles(full_name),sale_items(quantity,unit_cost),sale_payments(method)').eq('business_id',profile.businessId).order('created_at',{ascending:false}).limit(limit)
  if(error)throw error
  return (data??[]).map((s:any)=>({id:s.id,number:s.number,date:s.created_at,total:Number(s.total),subtotal:Number(s.subtotal),status:s.status,customer:s.customers?.name??'Consumidor final',cashier:s.profiles?.full_name??'',items:(s.sale_items??[]).reduce((n:number,i:any)=>n+Number(i.quantity),0),method:s.sale_payments?.[0]?.method??'—',cost:(s.sale_items??[]).reduce((n:number,i:any)=>n+Number(i.quantity)*Number(i.unit_cost),0)}))
}
