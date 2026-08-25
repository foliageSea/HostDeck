import archiveIconUrl from '@/assets/file-icons/mac-tahoe/application-x-archive.svg'
import audioIconUrl from '@/assets/file-icons/mac-tahoe/audio-x-generic.svg'
import blankIconUrl from '@/assets/file-icons/mac-tahoe/application-blank.svg'
import certificateIconUrl from '@/assets/file-icons/mac-tahoe/application-certificate.svg'
import codeIconUrl from '@/assets/file-icons/mac-tahoe/application-script-blank.svg'
import cssIconUrl from '@/assets/file-icons/mac-tahoe/text-css.svg'
import databaseIconUrl from '@/assets/file-icons/mac-tahoe/application-sql.svg'
import documentIconUrl from '@/assets/file-icons/mac-tahoe/text-x-generic.svg'
import folderIconUrl from '@/assets/file-icons/mac-tahoe/folder.svg'
import htmlIconUrl from '@/assets/file-icons/mac-tahoe/text-html.svg'
import imageIconUrl from '@/assets/file-icons/mac-tahoe/image-x-generic.svg'
import javaIconUrl from '@/assets/file-icons/mac-tahoe/text-x-java.svg'
import javascriptIconUrl from '@/assets/file-icons/mac-tahoe/text-x-javascript.svg'
import jsonIconUrl from '@/assets/file-icons/mac-tahoe/application-json.svg'
import keyIconUrl from '@/assets/file-icons/mac-tahoe/application-x-pem-key.svg'
import markdownIconUrl from '@/assets/file-icons/mac-tahoe/text-markdown.svg'
import officeDocumentIconUrl from '@/assets/file-icons/mac-tahoe/x-office-document.svg'
import pdfIconUrl from '@/assets/file-icons/mac-tahoe/application-pdf.svg'
import presentationIconUrl from '@/assets/file-icons/mac-tahoe/x-office-presentation.svg'
import pythonIconUrl from '@/assets/file-icons/mac-tahoe/text-x-python.svg'
import rustIconUrl from '@/assets/file-icons/mac-tahoe/text-rust.svg'
import shellIconUrl from '@/assets/file-icons/mac-tahoe/application-x-shellscript.svg'
import spreadsheetIconUrl from '@/assets/file-icons/mac-tahoe/x-office-spreadsheet.svg'
import tomlIconUrl from '@/assets/file-icons/mac-tahoe/application-toml.svg'
import typescriptIconUrl from '@/assets/file-icons/mac-tahoe/text-x-typescript.svg'
import unknownIconUrl from '@/assets/file-icons/mac-tahoe/unknown.svg'
import videoIconUrl from '@/assets/file-icons/mac-tahoe/video-x-generic.svg'
import xmlIconUrl from '@/assets/file-icons/mac-tahoe/text-xml.svg'
import yamlIconUrl from '@/assets/file-icons/mac-tahoe/text-yaml.svg'

export interface FileIconMeta {
  src: string
  previewType: FilePreviewType
}

export type FilePreviewType = 'image' | 'video' | null

interface FileIconTarget {
  filename: string
  isDirectory: boolean
}

function fileIcon(src: string, previewType: FilePreviewType = null): FileIconMeta {
  return { src, previewType }
}

export const directoryTreeIconUrl = folderIconUrl

const folderIcon = fileIcon(folderIconUrl)
const defaultFileIcon = fileIcon(unknownIconUrl)
const archiveIcon = fileIcon(archiveIconUrl)
const audioIcon = fileIcon(audioIconUrl)
const blankIcon = fileIcon(blankIconUrl)
const certificateIcon = fileIcon(certificateIconUrl)
const codeIcon = fileIcon(codeIconUrl)
const cssIcon = fileIcon(cssIconUrl)
const databaseIcon = fileIcon(databaseIconUrl)
const documentIcon = fileIcon(documentIconUrl)
const htmlIcon = fileIcon(htmlIconUrl)
const imageIcon = fileIcon(imageIconUrl, 'image')
const javaIcon = fileIcon(javaIconUrl)
const javascriptIcon = fileIcon(javascriptIconUrl)
const jsonIcon = fileIcon(jsonIconUrl)
const keyIcon = fileIcon(keyIconUrl)
const markdownIcon = fileIcon(markdownIconUrl)
const officeDocumentIcon = fileIcon(officeDocumentIconUrl)
const pdfIcon = fileIcon(pdfIconUrl)
const presentationIcon = fileIcon(presentationIconUrl)
const pythonIcon = fileIcon(pythonIconUrl)
const rustIcon = fileIcon(rustIconUrl)
const shellIcon = fileIcon(shellIconUrl)
const spreadsheetIcon = fileIcon(spreadsheetIconUrl)
const tomlIcon = fileIcon(tomlIconUrl)
const typescriptIcon = fileIcon(typescriptIconUrl)
const videoIcon = fileIcon(videoIconUrl, 'video')
const xmlIcon = fileIcon(xmlIconUrl)
const yamlIcon = fileIcon(yamlIconUrl)

const filenameIcons: Record<string, FileIconMeta> = {
  '.bash_history': blankIcon,
  '.bash_profile': shellIcon,
  '.bashrc': shellIcon,
  '.dockerignore': codeIcon,
  '.env': keyIcon,
  '.gitconfig': keyIcon,
  '.gitignore': codeIcon,
  '.npmrc': keyIcon,
  '.profile': shellIcon,
  '.ssh': folderIcon,
  '.vimrc': codeIcon,
  dockerfile: codeIcon,
  license: documentIcon,
  makefile: codeIcon,
  readme: markdownIcon,
}

const extensionIcons: Record<string, FileIconMeta> = {
  '7z': archiveIcon,
  aac: audioIcon,
  ape: audioIcon,
  apng: imageIcon,
  apk: archiveIcon,
  asc: keyIcon,
  avi: videoIcon,
  avif: imageIcon,
  bash: shellIcon,
  bat: shellIcon,
  bmp: imageIcon,
  bz2: archiveIcon,
  c: codeIcon,
  cer: certificateIcon,
  cert: certificateIcon,
  conf: keyIcon,
  config: keyIcon,
  cpp: codeIcon,
  crt: certificateIcon,
  cs: codeIcon,
  csr: certificateIcon,
  css: cssIcon,
  csv: spreadsheetIcon,
  cxx: codeIcon,
  dart: codeIcon,
  db: databaseIcon,
  deb: archiveIcon,
  doc: officeDocumentIcon,
  docx: officeDocumentIcon,
  env: keyIcon,
  fish: shellIcon,
  flac: audioIcon,
  flv: videoIcon,
  gif: imageIcon,
  go: codeIcon,
  gz: archiveIcon,
  h: codeIcon,
  heic: imageIcon,
  heif: imageIcon,
  hpp: codeIcon,
  htm: htmlIcon,
  html: htmlIcon,
  ico: imageIcon,
  ini: keyIcon,
  java: javaIcon,
  jar: archiveIcon,
  jpeg: imageIcon,
  jpg: imageIcon,
  js: javascriptIcon,
  json: jsonIcon,
  jsx: javascriptIcon,
  key: keyIcon,
  kt: codeIcon,
  kts: codeIcon,
  less: cssIcon,
  log: blankIcon,
  lua: codeIcon,
  m4a: audioIcon,
  m4v: videoIcon,
  md: markdownIcon,
  mkv: videoIcon,
  mov: videoIcon,
  mp3: audioIcon,
  mp4: videoIcon,
  odp: presentationIcon,
  ods: spreadsheetIcon,
  odt: officeDocumentIcon,
  ogg: audioIcon,
  ogv: videoIcon,
  opus: audioIcon,
  p12: certificateIcon,
  pem: certificateIcon,
  pdf: pdfIcon,
  pfx: certificateIcon,
  php: codeIcon,
  png: imageIcon,
  ppt: presentationIcon,
  pptx: presentationIcon,
  ps1: shellIcon,
  py: pythonIcon,
  rar: archiveIcon,
  rb: codeIcon,
  rpm: archiveIcon,
  rs: rustIcon,
  rtf: officeDocumentIcon,
  sass: cssIcon,
  scala: codeIcon,
  scss: cssIcon,
  sh: shellIcon,
  sqlite: databaseIcon,
  sqlite3: databaseIcon,
  sql: databaseIcon,
  svg: imageIcon,
  swift: codeIcon,
  tar: archiveIcon,
  tgz: archiveIcon,
  tif: imageIcon,
  tiff: imageIcon,
  toml: tomlIcon,
  ts: typescriptIcon,
  tsv: spreadsheetIcon,
  tsx: typescriptIcon,
  txt: blankIcon,
  vue: codeIcon,
  war: archiveIcon,
  wav: audioIcon,
  webm: videoIcon,
  webp: imageIcon,
  wma: audioIcon,
  wmv: videoIcon,
  xls: spreadsheetIcon,
  xlsx: spreadsheetIcon,
  xml: xmlIcon,
  xz: archiveIcon,
  yaml: yamlIcon,
  yml: yamlIcon,
  zip: archiveIcon,
  zsh: shellIcon,
}

function getFileExtension(filename: string) {
  const parts = filename.toLowerCase().split('.')
  return parts.length > 1 ? parts[parts.length - 1] : ''
}

export function getFileIcon(file: FileIconTarget) {
  if (file.isDirectory) {
    return folderIcon
  }

  const normalizedName = file.filename.toLowerCase()
  return (
    filenameIcons[normalizedName] ??
    extensionIcons[getFileExtension(normalizedName)] ??
    defaultFileIcon
  )
}

export function getFilePreviewType(file: FileIconTarget): FilePreviewType {
  return getFileIcon(file).previewType
}
