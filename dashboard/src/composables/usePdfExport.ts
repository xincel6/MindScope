import { ref } from 'vue'
import html2canvas from 'html2canvas'
import jsPDF from 'jspdf'
import dayjs from 'dayjs'
import * as echarts from 'echarts/core'

const A4_W = 210
const A4_H = 297
const MARGIN = 14
const CONTENT_W = A4_W - MARGIN * 2

const LEGAL_TITLE = '法律免责合规技术声明'
const LEGAL_BODY =
  '本报告仅作为人工智能技术驱动的心理健康辅助筛查结果，不能作为替代精神科临床医生核心病理确诊与处方开具的唯一医学诊断依据'

export interface PdfReportData {
  date: string
  mediaName: string
  bdiScore: number
  severityLabel: string
  severityColor: string
  suggestion: string
  inferenceTimeMs?: number
  patientInfo?: {
    patientId: string
    gender: string
    ageRange: string
    assessmentDate: string
  } | null
  subScales?: { cognitive: number; somatic: number; behavioral: number }
  subMax?: { cognitive: number; somatic: number; behavioral: number }
  treatment?: {
    level: string
    interventions: string[]
    monitoring: string
    guidelines: string
  }
  vlmSections?: { title: string; content: string }[]
  bdiHistory?: { time: string; score: number }[]
}

function esc(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function progressBar(percent: number, color = '#0d9488'): string {
  const p = Math.min(Math.max(percent, 0), 1)
  return `
    <div style="height:8px;background:#e8f4f8;border-radius:4px;overflow:hidden;">
      <div style="width:${(p * 100).toFixed(1)}%;height:100%;background:${color};border-radius:4px;"></div>
    </div>`
}

function sectionTitle(title: string): string {
  return `
    <div style="display:flex;align-items:center;gap:8px;margin:20px 0 12px;">
      <span style="width:3px;height:16px;background:linear-gradient(180deg,#14b8a6,#0891b2);border-radius:2px;"></span>
      <span style="font-size:15px;font-weight:700;color:#1e3a5f;">${esc(title)}</span>
    </div>`
}

function buildReportHtml(data: PdfReportData, chartImage: string | null): string {
  const patientBlock = data.patientInfo
    ? `
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px 24px;padding:14px 16px;background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;margin-bottom:16px;">
        <div style="display:flex;justify-content:space-between;font-size:13px;">
          <span style="color:#64748b;">受试者编号</span>
          <span style="color:#1e3a5f;font-weight:600;">${esc(data.patientInfo.patientId)}</span>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:13px;">
          <span style="color:#64748b;">性别</span>
          <span style="color:#1e3a5f;font-weight:600;">${esc(data.patientInfo.gender)}</span>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:13px;">
          <span style="color:#64748b;">年龄段</span>
          <span style="color:#1e3a5f;font-weight:600;">${esc(data.patientInfo.ageRange)} 岁</span>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:13px;">
          <span style="color:#64748b;">评估日期</span>
          <span style="color:#1e3a5f;font-weight:600;">${esc(data.patientInfo.assessmentDate)}</span>
        </div>
      </div>`
    : ''

  const subscaleBlock =
    data.subScales && data.subMax
      ? `
      ${sectionTitle('BDI-II 维度估计（模型推算）')}
      <p style="font-size:11px;color:#94a3b8;font-style:italic;margin:-6px 0 12px;">* 以下维度为基于总分的模型估算，非正式量表分项结果</p>
      ${[
        ['认知-情感维度', data.subScales.cognitive, data.subMax.cognitive],
        ['躯体症状维度', data.subScales.somatic, data.subMax.somatic],
        ['行为表现维度', data.subScales.behavioral, data.subMax.behavioral],
      ]
        .map(
          ([label, val, max]) => `
        <div style="margin-bottom:12px;">
          <div style="display:flex;justify-content:space-between;font-size:12px;color:#475569;margin-bottom:4px;">
            <span>${label}</span><span style="font-family:monospace;">${val}/${max}</span>
          </div>
          ${progressBar(Number(val) / Number(max))}
        </div>`,
        )
        .join('')}`
      : ''

  const treatmentBlock = data.treatment
    ? `
      ${sectionTitle(`临床干预建议 · ${data.treatment.level}`)}
      <ul style="margin:0 0 12px;padding-left:20px;color:#475569;font-size:13px;line-height:1.75;">
        ${data.treatment.interventions.map((i) => `<li style="margin-bottom:4px;">${esc(i)}</li>`).join('')}
      </ul>
      <p style="font-size:12px;color:#475569;line-height:1.65;margin-bottom:6px;"><strong style="color:#1e3a5f;">随访建议：</strong>${esc(data.treatment.monitoring)}</p>
      <p style="font-size:11px;color:#94a3b8;font-style:italic;line-height:1.55;">${esc(data.treatment.guidelines)}</p>`
    : ''

  const vlmBlock =
    data.vlmSections && data.vlmSections.length
      ? `
      ${sectionTitle('多模态面部分析')}
      ${data.vlmSections
        .map(
          (s) => `
        <div style="margin-bottom:12px;padding:12px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;">
          <div style="font-size:13px;font-weight:600;color:#1e3a5f;margin-bottom:6px;">${esc(s.title)}</div>
          <div style="font-size:12px;color:#475569;line-height:1.75;">${esc(s.content)}</div>
        </div>`,
        )
        .join('')}`
      : ''

  const chartBlock = chartImage
    ? `
      ${sectionTitle('BDI-II 评分曲线')}
      <div style="padding:12px;background:#fff;border:1px solid #e2e8f0;border-radius:8px;text-align:center;">
        <img src="${chartImage}" style="max-width:100%;height:auto;" alt="BDI曲线" />
      </div>`
    : data.bdiHistory && data.bdiHistory.length
      ? `
      ${sectionTitle('BDI-II 评分记录')}
      <table style="width:100%;border-collapse:collapse;font-size:12px;">
        <thead>
          <tr style="background:#f0f9ff;">
            <th style="padding:8px 12px;text-align:left;color:#64748b;border-bottom:1px solid #e2e8f0;">时间点</th>
            <th style="padding:8px 12px;text-align:right;color:#64748b;border-bottom:1px solid #e2e8f0;">BDI 评分</th>
          </tr>
        </thead>
        <tbody>
          ${data.bdiHistory
            .map(
              (p, i) => `
            <tr style="background:${i % 2 ? '#f8fafc' : '#fff'};">
              <td style="padding:7px 12px;color:#475569;border-bottom:1px solid #f1f5f9;">${esc(p.time)}</td>
              <td style="padding:7px 12px;text-align:right;font-family:monospace;color:#0d9488;font-weight:600;border-bottom:1px solid #f1f5f9;">${p.score}</td>
            </tr>`,
            )
            .join('')}
        </tbody>
      </table>`
      : ''

  const inferenceLine = data.inferenceTimeMs
    ? `<span style="font-size:12px;color:#64748b;">推理耗时 ${data.inferenceTimeMs.toFixed(1)} ms</span>`
    : ''

  return `
    <div style="width:100%;background:#ffffff;color:#1e3a5f;font-family:'PingFang SC','Microsoft YaHei','Helvetica Neue',sans-serif;line-height:1.6;box-sizing:border-box;">

      <!-- 页眉 -->
      <div style="display:flex;align-items:center;justify-content:space-between;padding-bottom:16px;border-bottom:2px solid #0d9488;margin-bottom:20px;">
        <div style="display:flex;align-items:center;gap:12px;">
          <div style="width:40px;height:40px;background:linear-gradient(135deg,#ecfdf5,#e0f2fe);border:1px solid #99f6e4;border-radius:10px;display:flex;align-items:center;justify-content:center;">
            <span style="font-size:20px;color:#0d9488;font-weight:700;">+</span>
          </div>
          <div>
            <div style="font-size:20px;font-weight:700;color:#0d9488;">抑郁症智能辅助诊断系统</div>
            <div style="font-size:11px;color:#94a3b8;margin-top:2px;">病理分析报告 · LMTformer 多模态 AI 辅助筛查</div>
          </div>
        </div>
        <div style="text-align:right;font-size:11px;color:#94a3b8;">
          <div>${esc(data.date)}</div>
          <div style="margin-top:2px;">素材：${esc(data.mediaName)}</div>
        </div>
      </div>

      <!-- 法律免责声明（置顶） -->
      <div style="padding:14px 16px;background:#fffbeb;border:1px solid #fcd34d;border-left:4px solid #f59e0b;border-radius:8px;margin-bottom:20px;">
        <div style="font-size:13px;font-weight:700;color:#92400e;margin-bottom:6px;">${LEGAL_TITLE}</div>
        <div style="font-size:12px;color:#78350f;line-height:1.75;">${LEGAL_BODY}</div>
      </div>

      ${patientBlock}

      <!-- BDI 评分卡片 -->
      ${sectionTitle('评估结果')}
      <div style="display:flex;align-items:center;justify-content:space-between;padding:20px 24px;background:linear-gradient(135deg,#ecfdf5 0%,#e0f2fe 100%);border:1px solid #99f6e4;border-left:4px solid ${esc(data.severityColor)};border-radius:10px;margin-bottom:8px;">
        <div>
          <div style="font-size:12px;color:#64748b;margin-bottom:4px;">BDI-II 总评分</div>
          <div style="display:flex;align-items:baseline;gap:4px;">
            <span style="font-size:48px;font-weight:700;color:#0d9488;font-family:monospace;line-height:1;">${data.bdiScore}</span>
            <span style="font-size:16px;color:#94a3b8;">分</span>
          </div>
          <div style="font-size:11px;color:#94a3b8;margin-top:4px;font-family:monospace;">评分范围 0–63</div>
        </div>
        <div style="text-align:right;">
          <div style="display:inline-block;padding:6px 16px;background:#fff;border:1px solid ${esc(data.severityColor)};border-radius:20px;font-size:14px;font-weight:700;color:${esc(data.severityColor)};">
            ${esc(data.severityLabel)}
          </div>
          ${inferenceLine ? `<div style="margin-top:8px;">${inferenceLine}</div>` : ''}
        </div>
      </div>

      <!-- 简要说明 -->
      <div style="padding:12px 14px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;font-size:12px;color:#475569;line-height:1.7;margin-bottom:4px;">
        ${esc(data.suggestion)}
      </div>

      ${chartBlock}
      ${subscaleBlock}
      ${treatmentBlock}
      ${vlmBlock}

      <!-- 页脚 -->
      <div style="margin-top:28px;padding-top:16px;border-top:1px solid #e2e8f0;">
        <div style="padding:10px 12px;background:#f8fafc;border-radius:6px;margin-bottom:10px;">
          <div style="font-size:11px;font-weight:600;color:#64748b;margin-bottom:4px;">${LEGAL_TITLE}</div>
          <div style="font-size:10px;color:#94a3b8;line-height:1.65;">${LEGAL_BODY}</div>
        </div>
        <div style="text-align:center;font-size:10px;color:#cbd5e1;">
          基于 MSSTformer 深度学习模型 · BDI-II 量表标准 · 报告生成时间 ${esc(data.date)}
        </div>
      </div>
    </div>`
}

async function captureChartImage(chartElement: HTMLElement | null): Promise<string | null> {
  if (!chartElement) return null

  const chartDom =
    (chartElement.querySelector('.chart-instance') as HTMLElement | null) ?? chartElement

  try {
    const inst = echarts.getInstanceByDom(chartDom)
    if (inst) {
      return inst.getDataURL({
        type: 'png',
        pixelRatio: 2,
        backgroundColor: '#ffffff',
      })
    }
  } catch {
    /* fallback below */
  }

  const canvas = chartDom.querySelector('canvas')
  if (canvas) return canvas.toDataURL('image/png')
  return null
}

export function usePdfExport() {
  const exporting = ref(false)

  async function exportReport(data: PdfReportData, chartElement: HTMLElement | null) {
    exporting.value = true

    const wrapper = document.createElement('div')
    wrapper.style.position = 'fixed'
    wrapper.style.left = '-9999px'
    wrapper.style.top = '0'
    wrapper.style.width = '794px'
    wrapper.style.padding = '32px 36px'
    wrapper.style.background = '#ffffff'
    wrapper.style.boxSizing = 'border-box'

    const chartImage = await captureChartImage(chartElement)
    wrapper.innerHTML = buildReportHtml(data, chartImage)
    document.body.appendChild(wrapper)

    try {
      await new Promise((r) => setTimeout(r, 120))

      const canvas = await html2canvas(wrapper, {
        scale: 2,
        backgroundColor: '#ffffff',
        logging: false,
        allowTaint: true,
        useCORS: true,
        windowWidth: 794,
      })

      const pdf = new jsPDF('p', 'mm', 'a4')
      const imgW = CONTENT_W
      const imgH = (canvas.height * imgW) / canvas.width
      const maxContentH = A4_H - MARGIN * 2

      if (imgH <= maxContentH) {
        pdf.addImage(canvas.toDataURL('image/jpeg', 0.92), 'JPEG', MARGIN, MARGIN, imgW, imgH)
      } else {
        let srcY = 0
        let page = 0
        const sliceH = (maxContentH / imgH) * canvas.height

        while (srcY < canvas.height) {
          if (page > 0) pdf.addPage()

          const remaining = canvas.height - srcY
          const h = Math.min(sliceH, remaining)
          const dstH = (h / canvas.height) * imgH

          const sliceCanvas = document.createElement('canvas')
          sliceCanvas.width = canvas.width
          sliceCanvas.height = Math.ceil(h)
          const ctx = sliceCanvas.getContext('2d')!
          ctx.fillStyle = '#ffffff'
          ctx.fillRect(0, 0, sliceCanvas.width, sliceCanvas.height)
          ctx.drawImage(canvas, 0, srcY, canvas.width, h, 0, 0, canvas.width, h)

          pdf.addImage(sliceCanvas.toDataURL('image/jpeg', 0.92), 'JPEG', MARGIN, MARGIN, imgW, dstH)

          srcY += h
          page++
        }
      }

      pdf.save(`depression_report_${dayjs().format('YYYYMMDD_HHmmss')}.pdf`)
    } finally {
      document.body.removeChild(wrapper)
      exporting.value = false
    }
  }

  return { exporting, exportReport }
}
