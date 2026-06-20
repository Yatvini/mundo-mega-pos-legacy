import type { Product, Sale } from './types'

export const products: Product[] = [
  { id:'1', name:'Coca-Cola Original', sku:'BEB-001', barcode:'7401005001012', category:'Bebidas', price:8.5, cost:5.2, stock:24, minStock:10, unit:'600 ml', emoji:'🥤', color:'#ef4444' },
  { id:'2', name:'Leche Entera Dos Pinos', sku:'LAC-014', barcode:'7441001600149', category:'Lácteos', price:12, cost:8.1, stock:8, minStock:10, unit:'1 litro', emoji:'🥛', color:'#60a5fa' },
  { id:'3', name:'Pan Blanco Bimbo', sku:'PAN-003', barcode:'7501000115604', category:'Panadería', price:18.5, cost:13.2, stock:12, minStock:6, unit:'560 g', emoji:'🍞', color:'#f59e0b' },
  { id:'4', name:'Huevos Grandes', sku:'HUE-001', barcode:'7400001001034', category:'Canasta básica', price:32, cost:25, stock:5, minStock:8, unit:'cartón 12', emoji:'🥚', color:'#fbbf24' },
  { id:'5', name:'Arroz Blanco Gallo Dorado', sku:'GRN-008', barcode:'7401002008168', category:'Granos', price:9.75, cost:6.6, stock:42, minStock:15, unit:'1 lb', emoji:'🍚', color:'#d6d3d1' },
  { id:'6', name:'Frijol Negro Del Monte', sku:'GRN-011', barcode:'7401004501127', category:'Granos', price:11.5, cost:7.8, stock:31, minStock:12, unit:'1 lb', emoji:'🫘', color:'#78350f' },
  { id:'7', name:'Jabón Protex Avena', sku:'HIG-021', barcode:'7509546074447', category:'Cuidado personal', price:7.25, cost:4.3, stock:18, minStock:8, unit:'110 g', emoji:'🧼', color:'#a78bfa' },
  { id:'8', name:'Papel Higiénico Scott', sku:'HOG-007', barcode:'7501943492121', category:'Hogar', price:21, cost:15.8, stock:14, minStock:8, unit:'paquete 4', emoji:'🧻', color:'#38bdf8' },
  { id:'9', name:'Tortrix Barbacoa', sku:'SNK-004', barcode:'7401003300414', category:'Snacks', price:2, cost:1.2, stock:65, minStock:20, unit:'28 g', emoji:'🌽', color:'#fb923c' },
  { id:'10', name:'Agua Pura Salvavidas', sku:'BEB-009', barcode:'7401005003009', category:'Bebidas', price:5, cost:2.6, stock:3, minStock:12, unit:'600 ml', emoji:'💧', color:'#0ea5e9' },
]

export const sales: Sale[] = [
  {id:'V-1048',date:'Hoy, 10:42',customer:'Consumidor final',items:4,total:58.50,method:'Efectivo',cashier:'Ana López',status:'Completada'},
  {id:'V-1047',date:'Hoy, 10:28',customer:'María González',items:2,total:29.75,method:'Tarjeta',cashier:'Ana López',status:'Completada'},
  {id:'V-1046',date:'Hoy, 09:56',customer:'Consumidor final',items:7,total:113.00,method:'Efectivo',cashier:'Ana López',status:'Completada'},
  {id:'V-1045',date:'Hoy, 09:31',customer:'José Ramírez',items:3,total:45.25,method:'Transferencia',cashier:'Carlos Ruiz',status:'Completada'},
  {id:'V-1044',date:'Hoy, 09:10',customer:'Consumidor final',items:1,total:18.50,method:'Efectivo',cashier:'Carlos Ruiz',status:'Anulada'},
]

export const money = (n:number) => new Intl.NumberFormat('es-GT',{style:'currency',currency:'GTQ'}).format(n)
