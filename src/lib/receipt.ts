export type ReceiptLine = { name:string; quantity:number; unitPrice:number; total:number }
export type ReceiptData = {
  businessName:string; taxId?:string; businessPhone?:string; branchName:string;
  branchAddress?:string; branchPhone?:string; saleNumber:string|number; cashier:string;
  customer?:string; date:string|Date; paymentMethod:string; subtotal:number; discount?:number;
  tax?:number; total:number; lines:ReceiptLine[]; footer?:string; paper?:'80mm'|'58mm'
}

const esc=(value:unknown)=>String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]!))
const gtq=(value:number)=>`Q ${Number(value).toFixed(2)}`

export function printThermalReceipt(data:ReceiptData){
  const paper=data.paper??((localStorage.getItem('receipt-paper') as '80mm'|'58mm')||'80mm')
  const frame=document.createElement('iframe');frame.setAttribute('aria-hidden','true');frame.style.position='fixed';frame.style.right='0';frame.style.bottom='0';frame.style.width='0';frame.style.height='0';frame.style.border='0';
  document.body.appendChild(frame);const doc=frame.contentDocument;if(!doc)return
  const lines=data.lines.map(l=>`<tr><td><b>${esc(l.quantity)} ×</b> ${esc(l.name)}<small>${gtq(l.unitPrice)} c/u</small></td><td>${gtq(l.total)}</td></tr>`).join('')
  doc.open();doc.write(`<!doctype html><html><head><meta charset="utf-8"><title>Ticket ${esc(data.saleNumber)}</title><style>
  @page{size:${paper} auto;margin:0}*{box-sizing:border-box}body{margin:0;background:white;color:#000;font-family:"Courier New",monospace;font-size:${paper==='58mm'?'10px':'12px'};line-height:1.3}.ticket{width:${paper};padding:${paper==='58mm'?'3mm':'5mm'};margin:0 auto}.center{text-align:center}.logo{font-size:${paper==='58mm'?'17px':'21px'};font-weight:900;letter-spacing:-1px}.muted{font-size:.82em}.dash{border-top:1px dashed #000;margin:8px 0}.meta{display:flex;justify-content:space-between;gap:8px;margin:2px 0}.meta span:last-child{text-align:right}table{width:100%;border-collapse:collapse}td{padding:4px 0;vertical-align:top}td:last-child{text-align:right;white-space:nowrap}td small{display:block;padding-left:18px;font-size:.75em}.total{font-size:1.35em;font-weight:900;border-top:2px solid #000;padding-top:6px;margin-top:3px}.qrbox{border:1px solid #000;padding:5px;margin:10px auto;width:max-content;font-weight:bold}.footer{margin-top:10px}.no-print{display:none}@media screen{body{background:#eee}.ticket{background:#fff;min-height:150mm}}
  </style></head><body><main class="ticket"><header class="center"><div class="logo">${esc(data.businessName)}</div><div>${esc(data.branchName)}</div>${data.taxId?`<div class="muted">NIT: ${esc(data.taxId)}</div>`:''}${data.branchAddress?`<div class="muted">${esc(data.branchAddress)}</div>`:''}${data.branchPhone?`<div class="muted">Tel. ${esc(data.branchPhone)}</div>`:''}</header><div class="dash"></div><div class="meta"><span>VENTA</span><b>#${esc(String(data.saleNumber).padStart(5,'0'))}</b></div><div class="meta"><span>Fecha</span><span>${esc(new Date(data.date).toLocaleString('es-GT'))}</span></div><div class="meta"><span>Cajero</span><span>${esc(data.cashier)}</span></div><div class="meta"><span>Cliente</span><span>${esc(data.customer||'Consumidor final')}</span></div><div class="dash"></div><table><tbody>${lines}</tbody></table><div class="dash"></div><div class="meta"><span>Subtotal</span><span>${gtq(data.subtotal)}</span></div>${data.discount?`<div class="meta"><span>Descuento</span><span>− ${gtq(data.discount)}</span></div>`:''}${data.tax?`<div class="meta"><span>Impuestos</span><span>${gtq(data.tax)}</span></div>`:''}<div class="meta total"><span>TOTAL</span><span>${gtq(data.total)}</span></div><div class="meta"><span>Pago</span><span>${esc(data.paymentMethod)}</span></div><div class="dash"></div><footer class="center footer"><b>¡Gracias por su compra!</b><div class="muted">${esc(data.footer||'Conserve este comprobante.')}</div><div class="muted">Mundo Mega POS</div></footer></main></body></html>`);doc.close()
  let printed=false;const run=()=>{if(printed)return;printed=true;frame.contentWindow?.focus();frame.contentWindow?.print();setTimeout(()=>frame.remove(),1200)}
  if(frame.contentWindow)frame.contentWindow.onload=run;setTimeout(run,350)
}
