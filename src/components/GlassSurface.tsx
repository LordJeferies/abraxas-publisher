import { useEffect, useRef } from 'react'

export function GlassSurface({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let instance: any
    let cancelled = false
    const init = async () => {
      try {
        const mod: any = await import('@ybouane/liquidglass')
        if (cancelled || !ref.current) return
        const host = ref.current.parentElement
        if (!host) return
        instance = await mod.LiquidGlass.init({
          root: host,
          glassElements: [ref.current],
          defaults: {
            blurAmount: 0.12,
            refraction: 0.25,
            chromAberration: 0.015,
            edgeHighlight: 0.04,
            cornerRadius: 18,
            shadowOpacity: 0.14,
          },
        })
      } catch {
        // CSS backdrop-filter remains as a safe fallback.
      }
    }
    init()
    return () => {
      cancelled = true
      instance?.destroy?.()
    }
  }, [])

  return <div ref={ref} className={`glass-surface ${className}`}>{children}</div>
}
