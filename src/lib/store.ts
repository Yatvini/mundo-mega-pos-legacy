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
  taxId: string
  businessPhone: string
  branchAddress: string
  branchPhone: string
}
export type Customer = { id:string; name:string; phone:string; email:string; taxId:string; points:number; createdAt:string }
export type Purchase = { id:string; supplier:string; invoice:string; date:string; total:number; paymentStatus:string }
export type CashData = { session:null|{id:string;openedAt:string;openingAmount:number}; movements:Array<{id:string;kind:string;amount:number;description:string;createdAt:string}>; payments:Array<{method:string;amount:number}>; refunds?:Array<{method:string;amount:number}> }
export type LiveSale = { id:string; number:number; date:string; total:number; subtotal:number; discount:number; tax:number; refunded:number; status:string; customer:string; cashier:string; items:number; method:string; cost:number; lines:Array<{id:string;name:string;quantity:number;unitPrice:number;total:number}> }
export type TeamMember = { id:string; fullName:string; role:'admin'|'supervisor'|'cashier'|'warehouse'; active:boolean; branchId:string; branchName:string }
export type TeamInvitation = { id:string; email:string; role:string; acceptedAt:string|null; createdAt:string }
export type Branch = { id:string; name:string; address:string; phone:string; active:boolean; createdAt:string }

export async function loadStore() {
  if (!supabase) throw new Error('Supabase no está configurado')
  const { data: auth } = await supabase.auth.getUser()
  if (!auth.user) throw new Error('Sesión no encontrada')
  const { data: row, error: profileError } = await supabase
    .from('profiles')
    .select('id,business_id,branch_id,full_name,role,businesses(name,tax_id,phone),branches(name,address,phone)')
    .eq('id', auth.user.id).single()
  if (profileError) throw profileError
  const profile: StoreProfile = {
    id: row.id, businessId: row.business_id, branchId: row.branch_id,
    fullName: row.full_name, role: row.role,
    businessName: (row.businesses as any)?.name ?? 'Mi minimarket',
    branchName: (row.branches as any)?.name ?? 'Sucursal Central',
    taxId: (row.businesses as any)?.tax_id ?? '', businessPhone:(row.businesses as any)?.phone??'',
    branchAddress:(row.branches as any)?.address??'', branchPhone:(row.branches as any)?.phone??'',
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
  const {data:branchRows,error:branchError}=await supabase.from('branches').select('id').eq('business_id',profile.businessId).eq('active',true)
  if(branchError)throw branchError
  const {error:inventoryError}=await supabase.from('inventory').insert((branchRows??[]).map(b=>({branch_id:b.id,product_id:product.id,stock:b.id===profile.branchId?input.stock:0})))
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
  if(!session)return {session:null,movements:[],payments:[],refunds:[]}
  const [{data:movements,error:me},{data:payments,error:pe},{data:returns,error:re}]=await Promise.all([
    supabase.from('cash_movements').select('id,kind,amount,description,created_at').eq('session_id',session.id).order('created_at',{ascending:false}),
    supabase.from('sale_payments').select('method,amount,sales!inner(session_id,status)').eq('sales.session_id',session.id).eq('sales.status','completed'),
    supabase.from('sale_returns').select('amount,sales!inner(session_id,sale_payments(method))').eq('sales.session_id',session.id)
  ])
  if(me)throw me;if(pe)throw pe;if(re)throw re
  const refundRows=(returns??[]).map((r:any)=>({method:r.sales?.sale_payments?.[0]?.method??'cash',amount:Number(r.amount)}))
  return {session:{id:session.id,openedAt:session.opened_at,openingAmount:Number(session.opening_amount)},movements:(movements??[]).map(m=>({id:m.id,kind:m.kind,amount:Number(m.amount),description:m.description,createdAt:m.created_at})),payments:[...(payments??[]).map(p=>({method:p.method,amount:Number(p.amount)})),...refundRows.map(r=>({method:r.method,amount:-r.amount}))],refunds:refundRows}
}

export async function openCash(profile:StoreProfile,amount:number){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_sessions').insert({branch_id:profile.branchId,user_id:profile.id,opening_amount:amount});if(error)throw error}
export async function addCashMovement(profile:StoreProfile,sessionId:string,kind:'income'|'expense',amount:number,description:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_movements').insert({session_id:sessionId,user_id:profile.id,kind,amount,description});if(error)throw error}
export async function closeCash(sessionId:string,closingAmount:number,expectedAmount:number){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('cash_sessions').update({closed_at:new Date().toISOString(),closing_amount:closingAmount,expected_amount:expectedAmount}).eq('id',sessionId);if(error)throw error}

export async function loadSales(profile:StoreProfile,limit=100):Promise<LiveSale[]>{
  if(!supabase)throw new Error('Supabase no está configurado')
  const {data,error}=await supabase.from('sales').select('id,number,created_at,total,subtotal,discount,tax,status,customers(name),profiles(full_name),sale_items(id,product_name,quantity,unit_cost,unit_price,total),sale_payments(method),sale_returns(amount)').eq('business_id',profile.businessId).order('created_at',{ascending:false}).limit(limit)
  if(error)throw error
  return (data??[]).map((s:any)=>{const refunded=(s.sale_returns??[]).reduce((n:number,r:any)=>n+Number(r.amount),0);return {id:s.id,number:s.number,date:s.created_at,total:Number(s.total)-refunded,subtotal:Number(s.subtotal),discount:Number(s.discount),tax:Number(s.tax),refunded,status:s.status,customer:s.customers?.name??'Consumidor final',cashier:s.profiles?.full_name??'',items:(s.sale_items??[]).reduce((n:number,i:any)=>n+Number(i.quantity),0),method:s.sale_payments?.[0]?.method??'—',cost:(s.sale_items??[]).reduce((n:number,i:any)=>n+Number(i.quantity)*Number(i.unit_cost),0),lines:(s.sale_items??[]).map((i:any)=>({id:i.id,name:i.product_name,quantity:Number(i.quantity),unitPrice:Number(i.unit_price),total:Number(i.total)}))}})
}
export async function cancelSale(saleId:string,reason:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('cancel_sale',{p_sale_id:saleId,p_reason:reason});if(error)throw error}
export async function returnSale(saleId:string,reason:string,items:Array<{sale_item_id:string;quantity:number}>){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('return_sale',{p_sale_id:saleId,p_reason:reason,p_items:items});if(error)throw error}

export async function loadTeam(profile:StoreProfile){
  if(!supabase)throw new Error('Supabase no está configurado')
  const [{data:members,error:me},{data:invites,error:ie}]=await Promise.all([
    supabase.from('profiles').select('id,full_name,role,active,branch_id,branches(name)').eq('business_id',profile.businessId).order('full_name'),
    supabase.from('team_invitations').select('id,email,role,accepted_at,created_at').eq('business_id',profile.businessId).order('created_at',{ascending:false})
  ])
  if(me)throw me;if(ie)throw ie
  return {members:(members??[]).map((m:any)=>({id:m.id,fullName:m.full_name,role:m.role,active:m.active,branchId:m.branch_id,branchName:m.branches?.name??''})) as TeamMember[],invites:(invites??[]).map(i=>({id:i.id,email:i.email,role:i.role,acceptedAt:i.accepted_at,createdAt:i.created_at})) as TeamInvitation[]}
}
export async function inviteTeamMember(profile:StoreProfile,email:string,role:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('team_invitations').upsert({business_id:profile.businessId,branch_id:profile.branchId,email:email.toLowerCase().trim(),role,invited_by:profile.id,accepted_at:null},{onConflict:'business_id,email'});if(error)throw error}
export async function updateTeamMember(memberId:string,changes:{role?:string;active?:boolean}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('profiles').update(changes).eq('id',memberId);if(error)throw error}
export async function deleteInvitation(id:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('team_invitations').delete().eq('id',id);if(error)throw error}

export async function loadBranches(profile:StoreProfile):Promise<Branch[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.from('branches').select('id,name,address,phone,active,created_at').eq('business_id',profile.businessId).order('created_at');if(error)throw error;return (data??[]).map(b=>({id:b.id,name:b.name,address:b.address??'',phone:b.phone??'',active:b.active,createdAt:b.created_at}))}
export async function createBranch(input:{name:string;address:string;phone:string}){if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('create_branch',{p_name:input.name,p_address:input.address,p_phone:input.phone});if(error)throw error;return data as string}
export async function updateBranch(id:string,changes:{name?:string;address?:string;phone?:string;active?:boolean}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('branches').update(changes).eq('id',id);if(error)throw error}
export async function switchBranch(id:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('switch_branch',{p_branch_id:id});if(error)throw error}
export async function assignMemberBranch(memberId:string,branchId:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('assign_member_branch',{p_member_id:memberId,p_branch_id:branchId});if(error)throw error}
