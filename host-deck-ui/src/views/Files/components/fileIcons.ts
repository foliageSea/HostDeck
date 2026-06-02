import {
  Archive,
  Certificate,
  Code,
  Csv,
  DataBase,
  Document,
  DocumentAudio,
  DocumentBlank,
  DocumentPdf,
  DocumentProtected,
  DocumentUnknown,
  DocumentVideo,
  DocumentWordProcessor,
  Encryption,
  Gif,
  Html,
  Image,
  Folder,
} from '@vicons/carbon'
import type { Component } from 'vue'

export type FileIconTone =
  | 'folder'
  | 'image'
  | 'video'
  | 'audio'
  | 'code'
  | 'document'
  | 'archive'
  | 'data'
  | 'secure'
  | 'default'

export interface FileIconMeta {
  icon: Component
  tone: FileIconTone
}

interface FileIconTarget {
  filename: string
  isDirectory: boolean
}

const folderIcon: FileIconMeta = { icon: Folder, tone: 'folder' }
const defaultFileIcon: FileIconMeta = { icon: DocumentUnknown, tone: 'default' }

const filenameIcons: Record<string, FileIconMeta> = {
  '.bash_history': { icon: DocumentBlank, tone: 'document' },
  '.bash_profile': { icon: Code, tone: 'code' },
  '.bashrc': { icon: Code, tone: 'code' },
  '.dockerignore': { icon: Code, tone: 'code' },
  '.env': { icon: Encryption, tone: 'secure' },
  '.gitconfig': { icon: DocumentProtected, tone: 'secure' },
  '.gitignore': { icon: Code, tone: 'code' },
  '.npmrc': { icon: DocumentProtected, tone: 'secure' },
  '.profile': { icon: Code, tone: 'code' },
  '.ssh': folderIcon,
  '.vimrc': { icon: Code, tone: 'code' },
  dockerfile: { icon: Code, tone: 'code' },
  license: { icon: Document, tone: 'document' },
  makefile: { icon: Code, tone: 'code' },
  readme: { icon: Document, tone: 'document' },
}

const extensionIcons: Record<string, FileIconMeta> = {
  '7z': { icon: Archive, tone: 'archive' },
  aac: { icon: DocumentAudio, tone: 'audio' },
  ape: { icon: DocumentAudio, tone: 'audio' },
  apng: { icon: Image, tone: 'image' },
  apk: { icon: Archive, tone: 'archive' },
  asc: { icon: Encryption, tone: 'secure' },
  avi: { icon: DocumentVideo, tone: 'video' },
  avif: { icon: Image, tone: 'image' },
  bash: { icon: Code, tone: 'code' },
  bat: { icon: Code, tone: 'code' },
  bmp: { icon: Image, tone: 'image' },
  bz2: { icon: Archive, tone: 'archive' },
  c: { icon: Code, tone: 'code' },
  cer: { icon: Certificate, tone: 'secure' },
  cert: { icon: Certificate, tone: 'secure' },
  conf: { icon: DocumentProtected, tone: 'secure' },
  config: { icon: DocumentProtected, tone: 'secure' },
  cpp: { icon: Code, tone: 'code' },
  crt: { icon: Certificate, tone: 'secure' },
  cs: { icon: Code, tone: 'code' },
  csr: { icon: Certificate, tone: 'secure' },
  css: { icon: Code, tone: 'code' },
  csv: { icon: Csv, tone: 'data' },
  cxx: { icon: Code, tone: 'code' },
  dart: { icon: Code, tone: 'code' },
  db: { icon: DataBase, tone: 'data' },
  deb: { icon: Archive, tone: 'archive' },
  doc: { icon: DocumentWordProcessor, tone: 'document' },
  docx: { icon: DocumentWordProcessor, tone: 'document' },
  env: { icon: Encryption, tone: 'secure' },
  fish: { icon: Code, tone: 'code' },
  flac: { icon: DocumentAudio, tone: 'audio' },
  flv: { icon: DocumentVideo, tone: 'video' },
  gif: { icon: Gif, tone: 'image' },
  go: { icon: Code, tone: 'code' },
  gz: { icon: Archive, tone: 'archive' },
  h: { icon: Code, tone: 'code' },
  heic: { icon: Image, tone: 'image' },
  heif: { icon: Image, tone: 'image' },
  hpp: { icon: Code, tone: 'code' },
  htm: { icon: Html, tone: 'code' },
  html: { icon: Html, tone: 'code' },
  ico: { icon: Image, tone: 'image' },
  ini: { icon: DocumentProtected, tone: 'secure' },
  java: { icon: Code, tone: 'code' },
  jar: { icon: Archive, tone: 'archive' },
  jpeg: { icon: Image, tone: 'image' },
  jpg: { icon: Image, tone: 'image' },
  js: { icon: Code, tone: 'code' },
  json: { icon: Code, tone: 'code' },
  jsx: { icon: Code, tone: 'code' },
  key: { icon: Encryption, tone: 'secure' },
  kt: { icon: Code, tone: 'code' },
  kts: { icon: Code, tone: 'code' },
  less: { icon: Code, tone: 'code' },
  log: { icon: DocumentBlank, tone: 'document' },
  lua: { icon: Code, tone: 'code' },
  m4a: { icon: DocumentAudio, tone: 'audio' },
  m4v: { icon: DocumentVideo, tone: 'video' },
  md: { icon: Document, tone: 'document' },
  mkv: { icon: DocumentVideo, tone: 'video' },
  mov: { icon: DocumentVideo, tone: 'video' },
  mp3: { icon: DocumentAudio, tone: 'audio' },
  mp4: { icon: DocumentVideo, tone: 'video' },
  odp: { icon: DocumentWordProcessor, tone: 'document' },
  ods: { icon: Csv, tone: 'data' },
  odt: { icon: DocumentWordProcessor, tone: 'document' },
  ogg: { icon: DocumentAudio, tone: 'audio' },
  ogv: { icon: DocumentVideo, tone: 'video' },
  opus: { icon: DocumentAudio, tone: 'audio' },
  p12: { icon: Certificate, tone: 'secure' },
  pem: { icon: Certificate, tone: 'secure' },
  pdf: { icon: DocumentPdf, tone: 'document' },
  pfx: { icon: Certificate, tone: 'secure' },
  php: { icon: Code, tone: 'code' },
  png: { icon: Image, tone: 'image' },
  ppt: { icon: DocumentWordProcessor, tone: 'document' },
  pptx: { icon: DocumentWordProcessor, tone: 'document' },
  ps1: { icon: Code, tone: 'code' },
  py: { icon: Code, tone: 'code' },
  rar: { icon: Archive, tone: 'archive' },
  rb: { icon: Code, tone: 'code' },
  rpm: { icon: Archive, tone: 'archive' },
  rs: { icon: Code, tone: 'code' },
  rtf: { icon: DocumentWordProcessor, tone: 'document' },
  sass: { icon: Code, tone: 'code' },
  scala: { icon: Code, tone: 'code' },
  scss: { icon: Code, tone: 'code' },
  sh: { icon: Code, tone: 'code' },
  sqlite: { icon: DataBase, tone: 'data' },
  sqlite3: { icon: DataBase, tone: 'data' },
  sql: { icon: DataBase, tone: 'data' },
  svg: { icon: Image, tone: 'image' },
  swift: { icon: Code, tone: 'code' },
  tar: { icon: Archive, tone: 'archive' },
  tgz: { icon: Archive, tone: 'archive' },
  tif: { icon: Image, tone: 'image' },
  tiff: { icon: Image, tone: 'image' },
  toml: { icon: Code, tone: 'code' },
  ts: { icon: Code, tone: 'code' },
  tsv: { icon: Csv, tone: 'data' },
  tsx: { icon: Code, tone: 'code' },
  txt: { icon: DocumentBlank, tone: 'document' },
  vue: { icon: Code, tone: 'code' },
  war: { icon: Archive, tone: 'archive' },
  wav: { icon: DocumentAudio, tone: 'audio' },
  webm: { icon: DocumentVideo, tone: 'video' },
  webp: { icon: Image, tone: 'image' },
  wma: { icon: DocumentAudio, tone: 'audio' },
  wmv: { icon: DocumentVideo, tone: 'video' },
  xls: { icon: Csv, tone: 'data' },
  xlsx: { icon: Csv, tone: 'data' },
  xml: { icon: Code, tone: 'code' },
  xz: { icon: Archive, tone: 'archive' },
  yaml: { icon: Code, tone: 'code' },
  yml: { icon: Code, tone: 'code' },
  zip: { icon: Archive, tone: 'archive' },
  zsh: { icon: Code, tone: 'code' },
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
  return filenameIcons[normalizedName] ?? extensionIcons[getFileExtension(normalizedName)] ?? defaultFileIcon
}

export function getFileIconClass(file: FileIconTarget) {
  return `file-icon-${getFileIcon(file).tone}`
}
