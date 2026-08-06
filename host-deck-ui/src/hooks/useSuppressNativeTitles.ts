import { onBeforeUnmount, onMounted } from 'vue'

export function useSuppressNativeTitles() {
  const suppressedNativeTitles = new WeakMap<Element, string>()

  function handleMouseOver(event: MouseEvent) {
    const target = event.target instanceof Element ? event.target.closest('[title]') : null
    if (!target || suppressedNativeTitles.has(target)) return

    const title = target.getAttribute('title')
    if (title === null) return

    suppressedNativeTitles.set(target, title)
    target.removeAttribute('title')
    target.addEventListener(
      'mouseleave',
      () => {
        const suppressedTitle = suppressedNativeTitles.get(target)
        if (suppressedTitle === undefined) return

        target.setAttribute('title', suppressedTitle)
        suppressedNativeTitles.delete(target)
      },
      { once: true },
    )
  }

  onMounted(() => {
    document.addEventListener('mouseover', handleMouseOver, true)
  })

  onBeforeUnmount(() => {
    document.removeEventListener('mouseover', handleMouseOver, true)
  })
}
