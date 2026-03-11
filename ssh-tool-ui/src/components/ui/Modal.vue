<template>
  <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center overflow-x-hidden overflow-y-auto outline-none focus:outline-none">
    <div class="fixed inset-0 bg-black opacity-50" @click="close"></div>
    <div class="relative w-full max-w-lg mx-auto my-6 z-50 px-4">
      <div class="relative flex flex-col w-full bg-white dark:bg-gray-800 border-0 rounded-lg shadow-lg outline-none focus:outline-none text-gray-900 dark:text-gray-100">
        <!-- Header -->
        <div class="flex items-center justify-between p-4 border-b border-solid border-slate-200 dark:border-gray-700 rounded-t">
          <h3 class="text-lg font-semibold">
            {{ title }}
          </h3>
          <button class="p-1 ml-auto bg-transparent border-0 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 float-right text-2xl leading-none font-semibold outline-none focus:outline-none" @click="close">
            <span class="bg-transparent h-6 w-6 block outline-none focus:outline-none">
              ×
            </span>
          </button>
        </div>
        <!-- Body -->
        <div class="relative p-6 flex-auto">
          <slot></slot>
        </div>
        <!-- Footer -->
        <div class="flex items-center justify-end p-4 border-t border-solid border-slate-200 dark:border-gray-700 rounded-b">
          <slot name="footer">
            <button class="text-gray-500 background-transparent font-bold uppercase px-6 py-2 text-sm outline-none focus:outline-none mr-1 mb-1 ease-linear transition-all duration-150 hover:bg-gray-100 dark:hover:bg-gray-700 rounded" type="button" @click="close">
              取消
            </button>
            <button class="bg-blue-500 text-white active:bg-blue-600 font-bold uppercase text-sm px-6 py-2 rounded shadow hover:shadow-lg outline-none focus:outline-none mr-1 mb-1 ease-linear transition-all duration-150" type="button" @click="confirm">
              确定
            </button>
          </slot>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  show: boolean
  title: string
}>()

const emit = defineEmits(['close', 'confirm'])

const close = () => {
  emit('close')
}

const confirm = () => {
  emit('confirm')
}
</script>
