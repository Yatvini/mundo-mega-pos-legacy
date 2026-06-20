export type Product = { id: string; name: string; sku: string; barcode: string; category: string; price: number; cost: number; stock: number; minStock: number; unit: string; emoji: string; color: string }
export type CartItem = Product & { quantity: number }
export type Sale = { id: string; date: string; customer: string; items: number; total: number; method: string; cashier: string; status: string }
