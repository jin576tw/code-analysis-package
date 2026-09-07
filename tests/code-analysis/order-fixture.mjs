// Synthetic source for skill behavior evaluation. No network or production data.
export async function cancelOrder(order, actor, services) {
  if (!actor.canCancel) return { status: 403, body: { error: 'forbidden' } };
  if (!order) return { status: 404, body: { error: 'not_found' } };
  if (order.status === 'cancelled') return { status: 200, body: { changed: false } };
  if (order.status === 'shipped') return { status: 409, body: { error: 'already_shipped' } };
  if (order.items.length > 0) await services.restock(order.items);
  order.status = 'cancelled';
  await services.save(order);
  if (order.paidAmount > 0) {
    try {
      await services.refund(order.id, order.paidAmount);
    } catch {
      return { status: 202, body: { changed: true, refundPending: true } };
    }
  }
  return { status: 200, body: { changed: true, refundPending: false } };
}
