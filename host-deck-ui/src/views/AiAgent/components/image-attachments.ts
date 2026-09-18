import type { AiAgentImageAttachment } from '@/api/ai-agent'

export const MAX_IMAGE_ATTACHMENTS = 4
export const MAX_IMAGE_BYTES = 8 * 1024 * 1024
export const MAX_TOTAL_IMAGE_BYTES = 20 * 1024 * 1024

const supportedImageTypes = new Set(['image/gif', 'image/jpeg', 'image/png', 'image/webp'])

export function imageAttachmentSrc(attachment: AiAgentImageAttachment) {
  return `data:${attachment.mimeType};base64,${attachment.data}`
}

export async function filesToImageAttachments(
  files: File[],
  existing: AiAgentImageAttachment[],
): Promise<{ attachments: AiAgentImageAttachment[]; rejected: string[] }> {
  const attachments = [...existing]
  const rejected: string[] = []
  let totalBytes = attachments.reduce(
    (total, attachment) => total + base64ByteLength(attachment.data),
    0,
  )

  for (const file of files) {
    if (attachments.length >= MAX_IMAGE_ATTACHMENTS) {
      rejected.push(`最多添加 ${MAX_IMAGE_ATTACHMENTS} 张图片`)
      break
    }
    const mimeType = file.type.toLowerCase()
    if (!supportedImageTypes.has(mimeType)) {
      rejected.push(`${file.name || '剪贴板图片'}：不支持该图片格式`)
      continue
    }
    if (file.size === 0 || file.size > MAX_IMAGE_BYTES) {
      rejected.push(`${file.name || '剪贴板图片'}：图片不能超过 8 MiB`)
      continue
    }
    if (totalBytes + file.size > MAX_TOTAL_IMAGE_BYTES) {
      rejected.push('图片总大小不能超过 20 MiB')
      break
    }
    attachments.push({
      data: await readFileBase64(file),
      mimeType,
      name: file.name || `截图-${attachments.length + 1}`,
    })
    totalBytes += file.size
  }

  return { attachments, rejected: [...new Set(rejected)] }
}

function readFileBase64(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error('读取图片失败。'))
    reader.onload = () => {
      const result = reader.result
      if (typeof result !== 'string') {
        reject(new Error('读取图片失败。'))
        return
      }
      resolve(result.slice(result.indexOf(',') + 1))
    }
    reader.readAsDataURL(file)
  })
}

function base64ByteLength(data: string) {
  const padding = data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0
  return Math.max(0, Math.floor((data.length * 3) / 4) - padding)
}
