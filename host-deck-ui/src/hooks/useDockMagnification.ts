import { onBeforeUnmount, onMounted, watch, type Ref } from 'vue'

export function useDockMagnification(rootRef: Ref<HTMLElement | null>, disabled: Ref<boolean>) {
  let frame = 0
  let cleanup: (() => void) | undefined

  onMounted(() => {
    const root = rootRef.value
    const track = root?.querySelector<HTMLElement>('.dock-track')
    if (!root || !track) return

    const motion = window.matchMedia('(prefers-reduced-motion: no-preference)')
    const hover = window.matchMedia('(any-hover: hover) and (any-pointer: fine)')
    let pointerX: number | undefined

    function render() {
      frame = 0
      const items = Array.from(track!.querySelectorAll<HTMLElement>('[data-dock-slot]')).filter(
        (item) => !item.classList.contains('dock-app-leave-active'),
      )
      const left = track!.getBoundingClientRect().left - track!.scrollLeft
      const sizes = items.map((item) => {
        if (item.classList.contains('dock-separator')) return { scale: 1, extra: 0 }

        // Measure layout positions, never animated bounds: magnification must not feed back
        // into pointer distance. Entries also have a positioned TransitionGroup ancestor.
        let offset = 0
        let ancestor: HTMLElement | null = item
        while (ancestor && ancestor !== track) {
          offset += ancestor.offsetLeft
          ancestor = ancestor.offsetParent as HTMLElement | null
        }
        const width = item.offsetWidth
        const distance = Math.abs((pointerX ?? Infinity) - (left + offset + width / 2))
        const influence = distance < 140 ? (1 + Math.cos((distance / 140) * Math.PI)) / 2 : 0
        return { scale: 1 + influence * 0.5, extra: width * influence * 0.5 }
      })

      const expansion = sizes.reduce((total, item) => total + item.extra, 0)
      root!.style.setProperty('--dock-expansion', `${expansion}px`)
      let shift = -expansion / 2
      items.forEach((item, index) => {
        const { scale, extra } = sizes[index]!
        item.style.setProperty('--dock-scale', String(scale))
        item.style.setProperty('--dock-shift', `${shift + extra / 2}px`)
        shift += extra
      })
    }

    function schedule() {
      if (!frame) frame = requestAnimationFrame(render)
    }

    function reset() {
      pointerX = undefined
      root!.removeAttribute('data-magnifying')
      schedule()
    }

    function move(event: PointerEvent) {
      if (
        event.pointerType === 'touch' ||
        disabled.value ||
        !motion.matches ||
        !hover.matches ||
        track!.scrollWidth > track!.clientWidth
      ) {
        reset()
        return
      }
      pointerX = event.clientX
      root!.setAttribute('data-magnifying', 'true')
      schedule()
    }

    const resize = new ResizeObserver(reset)
    resize.observe(track)
    const children = new MutationObserver(schedule)
    children.observe(track, { childList: true, subtree: true })
    const stopWatch = watch(disabled, reset, { flush: 'sync' })
    root.addEventListener('pointermove', move)
    root.addEventListener('pointerleave', reset)
    root.addEventListener('pointercancel', reset)
    track.addEventListener('scroll', reset, { passive: true })
    window.addEventListener('blur', reset)
    motion.addEventListener('change', reset)
    hover.addEventListener('change', reset)
    cleanup = () => {
      stopWatch()
      resize.disconnect()
      children.disconnect()
      root.removeEventListener('pointermove', move)
      root.removeEventListener('pointerleave', reset)
      root.removeEventListener('pointercancel', reset)
      track.removeEventListener('scroll', reset)
      window.removeEventListener('blur', reset)
      motion.removeEventListener('change', reset)
      hover.removeEventListener('change', reset)
    }
  })

  onBeforeUnmount(() => {
    cleanup?.()
    cancelAnimationFrame(frame)
  })
}
