import { describe, expect, it } from 'vitest'
import {
  filesToImageAttachments,
  imageAttachmentSrc,
  MAX_IMAGE_ATTACHMENTS,
} from '../image-attachments'

describe('AI Agent image attachments', () => {
  it('converts supported images to base64 data', async () => {
    const file = new File(['screenshot'], 'screen.png', { type: 'image/png' })

    const result = await filesToImageAttachments([file], [])

    expect(result.rejected).toEqual([])
    expect(result.attachments[0]).toMatchObject({ mimeType: 'image/png', name: 'screen.png' })
    expect(imageAttachmentSrc(result.attachments[0]!)).toBe(
      `data:image/png;base64,${result.attachments[0]!.data}`,
    )
  })

  it('rejects unsupported files and enforces the image count', async () => {
    const existing = Array.from({ length: MAX_IMAGE_ATTACHMENTS }, (_, index) => ({
      data: 'YQ==',
      mimeType: 'image/png',
      name: `${index}.png`,
    }))

    const unsupported = await filesToImageAttachments(
      [new File(['svg'], 'icon.svg', { type: 'image/svg+xml' })],
      [],
    )
    const full = await filesToImageAttachments(
      [new File(['image'], 'extra.png', { type: 'image/png' })],
      existing,
    )

    expect(unsupported.attachments).toEqual([])
    expect(unsupported.rejected[0]).toContain('不支持')
    expect(full.attachments).toHaveLength(MAX_IMAGE_ATTACHMENTS)
    expect(full.rejected[0]).toContain('最多')
  })
})
