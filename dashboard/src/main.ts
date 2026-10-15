import { createApp } from 'vue'
import { createPinia } from 'pinia'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import * as ElementPlusIconsVue from '@element-plus/icons-vue'
import VueECharts from 'vue-echarts'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart, GraphChart, PieChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent, VisualMapComponent } from 'echarts/components'
import router from './router'
import App from './App.vue'
import './style.css'
import { warmUpApiBase } from './api/baseResolver'

use([CanvasRenderer, LineChart, GraphChart, PieChart, GridComponent, TooltipComponent, LegendComponent, VisualMapComponent])

// 启动就后台探测后端地址（同源 → 本地 → 远程），别让用户第一次点击时才等探测
warmUpApiBase()

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(ElementPlus)
app.component('VChart', VueECharts)

for (const [key, component] of Object.entries(ElementPlusIconsVue)) {
  app.component(key, component)
}

app.mount('#app')
