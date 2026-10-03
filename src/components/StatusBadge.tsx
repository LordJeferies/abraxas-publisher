const labels: Record<string,string> = {
  EN_CONFIRMACION:'En confirmación', CON_CORRECCION:'Con corrección', LISTO_POR_PROGRAMAR:'Listo / por programar', PROGRAMADO:'Programado',
  VALID:'Validado', WARNING:'Advertencia', INVALID:'Inválido', PRECALENDARIZED:'Precalendarizado', READY:'Listo'
}
export function StatusBadge({ status }: { status: string }) {
  const key = status.toLowerCase().replaceAll('_','-')
  return <span className={`status status-${key}`}>{labels[status] || status.replaceAll('_',' ')}</span>
}
