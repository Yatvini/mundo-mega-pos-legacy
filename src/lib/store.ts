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
export type BranchReport = { branchId:string;branchName:string;active:boolean;grossSales:number;refunds:number;netSales:number;transactions:number;averageTicket:number;costOfSales:number;grossProfit:number;margin:number;inventoryValue:number;lowStock:number;outOfStock:number }
export type ControlMovement = { id:string;date:string;branchId:string;branchName:string;type:string;description:string;userName:string;amount:number }
export type ControlInventory = { productId:string;productName:string;sku:string;category:string;totalStock:number;minStock:number;cost:number;inventoryValue:number;stockByBranch:Record<string,number> }
export type PlatformSummary = { businesses:number;activeBusinesses:number;pendingBusinesses:number;suspendedBusinesses:number;branches:number;users:number;salesToday:number }
export type PlatformBusiness = { id:string;name:string;legalName:string;slug:string;industry:string;plan:string;status:string;slogan:string;primaryColor:string;accentColor:string;modules:Record<string,boolean>;maxBranches:number;maxUsers:number;branches:number;users:number;products:number;salesTotal:number;createdAt:string }
export type InvitationEmailResult = { ok:boolean; mode:'invite'|'password'; message:string }
export type CashClosureMovement = { id:string;createdAt:string;userName:string;paymentMethod:string;kind:'income'|'expense';amount:number;description:string }
export type CashClosureReport = { sessionId:string;branchId:string;branchName:string;openedAt:string;closedAt:string;userName:string;openingAmount:number;expectedAmount:number;closingAmount:number;difference:number;cashSales:number;cardSales:number;transferSales:number;creditSales:number;manualIncome:number;manualExpense:number;refunds:number;totalSales:number;movements?:CashClosureMovement[] }
export type AttendanceEmployee = { id:string;branchId:string|null;branchName:string;fullName:string;position:string;baseSalary:number;active:boolean;createdAt:string }
export type AttendanceCategory = { id:string;name:string;kind:'start_shift'|'lunch_out'|'lunch_in'|'end_shift'|'custom';sortOrder:number;active:boolean }
export type AttendanceEvent = { id:string;employeeId:string;employeeName:string;categoryId:string;categoryName:string;categoryKind:string;branchName:string;markedAt:string;note:string }
export type AttendanceKioskData = { business:{id:string;name:string};branch:{id:string;name:string}|null;employees:Array<{id:string;fullName:string;position:string}>;categories:Array<{id:string;name:string;kind:string}> }

async function sendInvitationEmail(input:{kind:'platform-business-admin'|'team-member';email:string;fullName?:string;businessId?:string}):Promise<InvitationEmailResult>{
  if(!supabase)throw new Error('Supabase no estÃ¡ configurado')
  const {data:{session}}=await supabase.auth.getSession()
  if(!session)throw new Error('SesiÃ³n no encontrada')
  const response=await fetch('/api/send-invitation-email',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},body:JSON.stringify({...input,redirectTo:`${window.location.origin}/?invite=1`})})
  const payload=await response.json().catch(()=>({}))
  if(!response.ok)throw new Error(payload.error||'No fue posible enviar el correo de invitaciÃ³n')
  return payload as InvitationEmailResult
}

export async function checkPlatformAdmin(){if(!supabase)return false;const {data,error}=await supabase.rpc('is_platform_admin');if(error)throw error;return Boolean(data)}
export async function loadPlatformSummary():Promise<PlatformSummary>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('platform_summary');if(error)throw error;const x=data??{};return {businesses:Number(x.businesses??0),activeBusinesses:Number(x.activeBusinesses??0),pendingBusinesses:Number(x.pendingBusinesses??0),suspendedBusinesses:Number(x.suspendedBusinesses??0),branches:Number(x.branches??0),users:Number(x.users??0),salesToday:Number(x.salesToday??0)}}
export async function loadPlatformBusinesses():Promise<PlatformBusiness[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('platform_list_businesses');if(error)throw error;return (data??[]).map((b:any)=>({id:b.id,name:b.name,legalName:b.legal_name??'',slug:b.slug,industry:b.industry,plan:b.plan,status:b.status,slogan:b.slogan??'',primaryColor:b.primary_color,accentColor:b.accent_color,modules:b.modules??{},maxBranches:Number(b.max_branches),maxUsers:Number(b.max_users),branches:Number(b.branches),users:Number(b.users),products:Number(b.products),salesTotal:Number(b.sales_total),createdAt:b.created_at}))}
export async function createPlatformBusiness(input:{name:string;legalName:string;industry:string;adminEmail:string;adminName:string;plan:string;slogan:string;primaryColor:string;accentColor:string}){if(!supabase)throw new Error('Supabase no esta configurado');const {data,error}=await supabase.rpc('platform_create_business',{p_name:input.name,p_legal_name:input.legalName,p_industry:input.industry,p_admin_email:input.adminEmail,p_admin_name:input.adminName||null,p_plan:input.plan,p_slogan:input.slogan||null,p_primary_color:input.primaryColor,p_accent_color:input.accentColor});if(error)throw error;const businessId=data as string;const emailResult=await sendInvitationEmail({kind:'platform-business-admin',businessId,email:input.adminEmail,fullName:input.adminName});return {businessId,emailResult}}
export async function updatePlatformBusiness(id:string,changes:{status?:string;plan?:string;name?:string;legalName?:string;industry?:string;slogan?:string;primaryColor?:string;accentColor?:string;modules?:Record<string,boolean>}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('platform_update_business',{p_business_id:id,p_status:changes.status??null,p_plan:changes.plan??null,p_name:changes.name??null,p_industry:changes.industry??null,p_slogan:changes.slogan??null,p_modules:changes.modules??null,p_legal_name:changes.legalName??null,p_primary_color:changes.primaryColor??null,p_accent_color:changes.accentColor??null});if(error)throw error}
export async function deletePlatformBusiness(id:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('platform_delete_business',{p_business_id:id});if(error)throw error}
export async function resendPlatformInvitation(id:string,email:string,fullName:string){if(!supabase)throw new Error('Supabase no esta configurado');const {error}=await supabase.rpc('platform_resend_business_invitation',{p_business_id:id,p_email:email,p_full_name:fullName||null});if(error)throw error;return sendInvitationEmail({kind:'platform-business-admin',businessId:id,email,fullName})}
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
  const {data,error}=await supabase.from('sales').select('id,number,created_at,total,subtotal,discount,tax,status,customers(name),profiles(full_name),sale_items(id,product_name,quantity,unit_cost,unit_price,total),sale_payments(method),sale_returns(amount)').eq('business_id',profile.businessId).eq('branch_id',profile.branchId).order('created_at',{ascending:false}).limit(limit)
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
export async function inviteTeamMember(profile:StoreProfile,email:string,role:string){if(!supabase)throw new Error('Supabase no esta configurado');const {error}=await supabase.from('team_invitations').upsert({business_id:profile.businessId,branch_id:profile.branchId,email:email.toLowerCase().trim(),role,invited_by:profile.id,accepted_at:null},{onConflict:'business_id,email'});if(error)throw error;return sendInvitationEmail({kind:'team-member',email,fullName:''})}
export async function updateTeamMember(memberId:string,changes:{role?:string;active?:boolean}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('profiles').update(changes).eq('id',memberId);if(error)throw error}
export async function deleteInvitation(id:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('team_invitations').delete().eq('id',id);if(error)throw error}

export async function loadBranches(profile:StoreProfile):Promise<Branch[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.from('branches').select('id,name,address,phone,active,created_at').eq('business_id',profile.businessId).order('created_at');if(error)throw error;return (data??[]).map(b=>({id:b.id,name:b.name,address:b.address??'',phone:b.phone??'',active:b.active,createdAt:b.created_at}))}
export async function createBranch(input:{name:string;address:string;phone:string}){if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('create_branch',{p_name:input.name,p_address:input.address,p_phone:input.phone});if(error)throw error;return data as string}
export async function updateBranch(id:string,changes:{name?:string;address?:string;phone?:string;active?:boolean}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('branches').update(changes).eq('id',id);if(error)throw error}
export async function switchBranch(id:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('switch_branch',{p_branch_id:id});if(error)throw error}
export async function assignMemberBranch(memberId:string,branchId:string){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.rpc('assign_member_branch',{p_member_id:memberId,p_branch_id:branchId});if(error)throw error}
export async function loadBranchControl(from:Date,to:Date):Promise<BranchReport[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('branch_control_report_v2',{p_from:from.toISOString(),p_to:to.toISOString()});if(error)throw error;return (data??[]).map((r:any)=>({branchId:r.branch_id,branchName:r.branch_name,active:r.active,grossSales:Number(r.gross_sales),refunds:Number(r.refunds),netSales:Number(r.net_sales),transactions:Number(r.transactions),averageTicket:Number(r.average_ticket),costOfSales:Number(r.cost_of_sales),grossProfit:Number(r.gross_profit),margin:Number(r.margin),inventoryValue:Number(r.inventory_value),lowStock:Number(r.low_stock),outOfStock:Number(r.out_of_stock)}))}
export async function loadControlMovements(from:Date,to:Date,branchId?:string):Promise<ControlMovement[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('control_center_movements',{p_from:from.toISOString(),p_to:to.toISOString(),p_branch_id:branchId||null});if(error)throw error;return (data??[]).map((r:any)=>({id:r.event_id,date:r.event_date,branchId:r.branch_id,branchName:r.branch_name,type:r.event_type,description:r.description,userName:r.user_name,amount:Number(r.amount)}))}
export async function loadControlInventory():Promise<ControlInventory[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('control_center_inventory');if(error)throw error;return (data??[]).map((r:any)=>({productId:r.product_id,productName:r.product_name,sku:r.sku,category:r.category,totalStock:Number(r.total_stock),minStock:Number(r.min_stock),cost:Number(r.cost),inventoryValue:Number(r.inventory_value),stockByBranch:r.stock_by_branch??{}}))}
export async function loadCashClosureReports(from:Date,to:Date,branchId?:string):Promise<CashClosureReport[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('cash_closure_reports',{p_from:from.toISOString(),p_to:to.toISOString(),p_branch_id:branchId||null});if(error)throw error;return (data??[]).map((r:any)=>({sessionId:r.session_id,branchId:r.branch_id,branchName:r.branch_name,openedAt:r.opened_at,closedAt:r.closed_at,userName:r.user_name,openingAmount:Number(r.opening_amount),expectedAmount:Number(r.expected_amount),closingAmount:Number(r.closing_amount),difference:Number(r.difference),cashSales:Number(r.cash_sales),cardSales:Number(r.card_sales),transferSales:Number(r.transfer_sales),creditSales:Number(r.credit_sales),manualIncome:Number(r.manual_income),manualExpense:Number(r.manual_expense),refunds:Number(r.refunds),totalSales:Number(r.total_sales)}))}
export async function loadCashClosureMovements(sessionId:string):Promise<CashClosureMovement[]>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('cash_closure_movement_details',{p_session_id:sessionId});if(error)throw error;return (data??[]).map((m:any)=>({id:m.movement_id,createdAt:m.created_at,userName:m.user_name,paymentMethod:m.payment_method,kind:m.kind,amount:Number(m.amount),description:m.description}))}
export async function ensureAttendanceKiosk(branchId?:string){if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('attendance_ensure_kiosk',{p_branch_id:branchId||null});if(error)throw error;return data?.[0]?.token as string}
export async function loadAttendanceAdmin(profile:StoreProfile,from:Date,to:Date){if(!supabase)throw new Error('Supabase no está configurado');const [employees,categories,events]=await Promise.all([supabase.from('attendance_employees').select('id,branch_id,full_name,position,base_salary,active,created_at,branches(name)').eq('business_id',profile.businessId).order('full_name'),supabase.from('attendance_categories').select('id,name,kind,sort_order,active').eq('business_id',profile.businessId).order('sort_order'),supabase.from('attendance_events').select('id,employee_id,category_id,marked_at,note,attendance_employees(full_name),attendance_categories(name,kind),branches(name)').eq('business_id',profile.businessId).gte('marked_at',from.toISOString()).lte('marked_at',to.toISOString()).order('marked_at',{ascending:false})]);if(employees.error)throw employees.error;if(categories.error)throw categories.error;if(events.error)throw events.error;return {employees:(employees.data??[]).map((e:any)=>({id:e.id,branchId:e.branch_id,branchName:e.branches?.name??'General',fullName:e.full_name,position:e.position??'',baseSalary:Number(e.base_salary),active:e.active,createdAt:e.created_at})) as AttendanceEmployee[],categories:(categories.data??[]).map((c:any)=>({id:c.id,name:c.name,kind:c.kind,sortOrder:c.sort_order,active:c.active})) as AttendanceCategory[],events:(events.data??[]).map((e:any)=>({id:e.id,employeeId:e.employee_id,employeeName:e.attendance_employees?.full_name??'',categoryId:e.category_id,categoryName:e.attendance_categories?.name??'',categoryKind:e.attendance_categories?.kind??'custom',branchName:e.branches?.name??'General',markedAt:e.marked_at,note:e.note??''})) as AttendanceEvent[]}}
export async function createAttendanceEmployee(profile:StoreProfile,input:{fullName:string;position:string;baseSalary:number;branchId?:string}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('attendance_employees').insert({business_id:profile.businessId,branch_id:input.branchId||profile.branchId,full_name:input.fullName,position:input.position||null,base_salary:input.baseSalary});if(error)throw error}
export async function updateAttendanceEmployee(id:string,changes:{active?:boolean;baseSalary?:number;position?:string}){if(!supabase)throw new Error('Supabase no está configurado');const payload:any={};if(changes.active!==undefined)payload.active=changes.active;if(changes.baseSalary!==undefined)payload.base_salary=changes.baseSalary;if(changes.position!==undefined)payload.position=changes.position;const {error}=await supabase.from('attendance_employees').update(payload).eq('id',id);if(error)throw error}
export async function createAttendanceCategory(profile:StoreProfile,input:{name:string;kind:string}){if(!supabase)throw new Error('Supabase no está configurado');const {error}=await supabase.from('attendance_categories').insert({business_id:profile.businessId,name:input.name,kind:input.kind,sort_order:90});if(error)throw error}
export async function getAttendanceKioskData(token:string):Promise<AttendanceKioskData>{if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('attendance_kiosk_data',{p_token:token});if(error)throw error;return data as AttendanceKioskData}
export async function markAttendance(token:string,employeeId:string,categoryId:string,note=''){if(!supabase)throw new Error('Supabase no está configurado');const {data,error}=await supabase.rpc('attendance_mark',{p_token:token,p_employee_id:employeeId,p_category_id:categoryId,p_note:note||null});if(error)throw error;return data as {id:string;markedAt:string;employeeName:string;categoryName:string}}
