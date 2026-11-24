from __future__ import annotations

from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(r"D:\3DGS")
OUTPUT = ROOT / "docs" / "毕业设计工作进度记录.docx"

BLUE = "2E74B5"
DARK_BLUE = "1F4D78"
NAVY = "20384D"
MUTED = "667085"
LIGHT_BLUE = "EAF2F8"
LIGHT_GRAY = "F2F4F7"
LIGHT_GREEN = "EAF6EE"
LIGHT_AMBER = "FFF4E5"
RED = "B42318"
WHITE = "FFFFFF"
BLACK = "000000"


def set_font(run, size=11, bold=False, color=BLACK, east_asia="微软雅黑", italic=False):
    run.font.name = "Calibri"
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), east_asia)
    run.font.size = Pt(size)
    run.bold = bold
    run.italic = italic
    run.font.color.rgb = RGBColor.from_string(color)


def shade_cell(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=80, start=120, bottom=80, end=120):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_geometry(table, widths):
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    total = sum(widths)
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(total))
    tbl_w.set(qn("w:type"), "dxa")
    tbl_ind = tbl_pr.find(qn("w:tblInd"))
    if tbl_ind is None:
        tbl_ind = OxmlElement("w:tblInd")
        tbl_pr.append(tbl_ind)
    tbl_ind.set(qn("w:w"), "120")
    tbl_ind.set(qn("w:type"), "dxa")

    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(width))
        grid.append(col)

    for row in table.rows:
        for idx, cell in enumerate(row.cells):
            width = widths[min(idx, len(widths) - 1)]
            cell.width = Inches(width / 1440)
            tc_pr = cell._tc.get_or_add_tcPr()
            tc_w = tc_pr.find(qn("w:tcW"))
            if tc_w is None:
                tc_w = OxmlElement("w:tcW")
                tc_pr.append(tc_w)
            tc_w.set(qn("w:w"), str(width))
            tc_w.set(qn("w:type"), "dxa")
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def keep_with_next(paragraph):
    paragraph.paragraph_format.keep_with_next = True


def add_page_field(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run("第 ")
    set_font(run, 9, color=MUTED)
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    paragraph._p.append(fld)
    run = paragraph.add_run(" 页")
    set_font(run, 9, color=MUTED)


def add_heading(doc, text, level=1):
    p = doc.add_paragraph(style=f"Heading {level}")
    p.add_run(text)
    keep_with_next(p)
    return p


def add_body(doc, text, bold_prefix=None):
    p = doc.add_paragraph()
    if bold_prefix and text.startswith(bold_prefix):
        a = p.add_run(bold_prefix)
        set_font(a, bold=True)
        b = p.add_run(text[len(bold_prefix):])
        set_font(b)
    else:
        r = p.add_run(text)
        set_font(r)
    return p


def add_bullet(doc, text, level=0):
    p = doc.add_paragraph(style="List Bullet" if level == 0 else "List Bullet 2")
    r = p.add_run(text)
    set_font(r)
    return p


def add_number(doc, text):
    p = doc.add_paragraph(style="List Number")
    r = p.add_run(text)
    set_font(r)
    return p


def add_callout(doc, label, text, fill=LIGHT_BLUE, label_color=DARK_BLUE):
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    set_table_geometry(table, [9360])
    cell = table.cell(0, 0)
    shade_cell(cell, fill)
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(0)
    a = p.add_run(label + "  ")
    set_font(a, 11, bold=True, color=label_color)
    b = p.add_run(text)
    set_font(b, 10.5, color=NAVY)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)
    return table


def add_table(doc, headers, rows, widths, aligns=None, keep_together=False):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    set_table_geometry(table, widths)
    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        shade_cell(cell, LIGHT_GRAY)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(header)
        set_font(r, 10, bold=True, color=NAVY)
    tr_pr = table.rows[0]._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)
    cant_split = OxmlElement("w:cantSplit")
    cant_split.set(qn("w:val"), "true")
    tr_pr.append(cant_split)
    for row in rows:
        table_row = table.add_row()
        row_pr = table_row._tr.get_or_add_trPr()
        cant_split = OxmlElement("w:cantSplit")
        cant_split.set(qn("w:val"), "true")
        row_pr.append(cant_split)
        cells = table_row.cells
        for idx, value in enumerate(row):
            p = cells[idx].paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.alignment = aligns[idx] if aligns else WD_ALIGN_PARAGRAPH.LEFT
            r = p.add_run(str(value))
            set_font(r, 9.5)
    set_table_geometry(table, widths)
    if keep_together:
        for row in table.rows[:-1]:
            for cell in row.cells:
                for paragraph in cell.paragraphs:
                    paragraph.paragraph_format.keep_with_next = True
    doc.add_paragraph().paragraph_format.space_after = Pt(0)
    return table


def build():
    doc = Document()
    section = doc.sections[0]
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(0.78)
    section.bottom_margin = Inches(0.72)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)
    section.header_distance = Inches(0.35)
    section.footer_distance = Inches(0.35)

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Calibri"
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
    normal.font.size = Pt(11)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.10

    for name, size, color, before, after in (
        ("Heading 1", 16, BLUE, 16, 8),
        ("Heading 2", 13, BLUE, 12, 6),
        ("Heading 3", 12, DARK_BLUE, 8, 4),
    ):
        style = styles[name]
        style.font.name = "Calibri"
        style._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(color)
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True

    for name in ("List Bullet", "List Bullet 2", "List Number"):
        style = styles[name]
        style.font.name = "Calibri"
        style._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
        style.font.size = Pt(11)
        style.paragraph_format.space_after = Pt(4)
        style.paragraph_format.line_spacing = 1.167

    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.LEFT
    a = header.add_run("3DGS 硬件加速器毕业设计")
    set_font(a, 9, bold=True, color=MUTED)
    b = header.add_run("   |   本地保密工作记录")
    set_font(b, 9, color=MUTED)
    add_page_field(section.footer.paragraphs[0])

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(3)
    r = p.add_run("毕业设计工作进度记录")
    set_font(r, 24, bold=True, color=NAVY)
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(14)
    r = p.add_run("面向三维高斯泼溅渲染的动态可重构硬件加速系统")
    set_font(r, 13, color=MUTED)

    meta = [
        ("当前阶段", "阶段 10：alpha与blend RTL数值闭环"),
        ("记录版本", "v0.9"),
        ("更新时间", "2026-08-04"),
        ("总体状态", "16个SV模块；74项测试通过；保半正定alpha与blend状态闭环完成"),
        ("保密边界", "全部材料仅在 D:\\3DGS 本地工作区处理，不上传网络或公开平台"),
    ]
    table = doc.add_table(rows=0, cols=2)
    table.style = "Table Grid"
    for label, value in meta:
        cells = table.add_row().cells
        shade_cell(cells[0], LIGHT_GRAY)
        p0 = cells[0].paragraphs[0]
        p0.paragraph_format.space_after = Pt(0)
        r0 = p0.add_run(label)
        set_font(r0, 10, bold=True, color=NAVY)
        p1 = cells[1].paragraphs[0]
        p1.paragraph_format.space_after = Pt(0)
        r1 = p1.add_run(value)
        set_font(r1, 10)
    set_table_geometry(table, [2100, 7260])
    doc.add_paragraph().paragraph_format.space_after = Pt(0)

    add_callout(
        doc,
        "核心研究问题",
        "在固定面积、片上容量和外存带宽约束下，Gaussian-wise数据流与粗粒度动态资源配置能否比固定功能基线获得更高的跨场景平均利用率和能效，同时保持图像质量。",
    )

    add_heading(doc, "1. 当前进展总览", 1)
    add_table(
        doc,
        ["工作包", "状态", "本轮产出", "下一检查点"],
        [
            ("研究范围与指标", "已冻结 v0.8", "完整SV RTL、三项画质指标、具体节点PPA", "冻结顶层与寄存器表"),
            ("系统数据流", "周期级首版完成", "多枢轴分组、精排、SH、alpha/混合重叠", "加入反馈延迟与存储冲突"),
            ("固定功能基线 B0", "首版完成", "周期、队列、scoreboard及逻辑流量模型", "用RTL和真实负载校准"),
            ("真实数据", "多位置抽样完成", "3视角完整投影；每视角3×3精确ROI", "扩展更多场景/相机"),
            ("可重构架构", "结论已修订", "终止感知低频模式选择；固定光栅优先作基线", "用ASIC PPA复核粒度"),
            ("RTL设计", "数值闭环首版完成", "alpha、blend、图像状态、APB、顶层子集", "SV编译与lint"),
            ("实验评估", "Cholesky扫描完成", "90万样本；分类不一致降至0.186%", "整图PSNR/SSIM/LPIPS"),
        ],
        [2160, 1320, 3300, 2580],
        [WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.LEFT],
    )

    add_heading(doc, "2. 已冻结的研究边界", 1)
    add_heading(doc, "2.1 必须完成", 2)
    for item in (
        "Gaussian-wise功能模型及逐像素正确性对照。",
        "全局深度分组、组内精排、块级alpha计算和顺序混合。",
        "固定功能B0与可重构R0的周期级性能和数据移动模型。",
        "关键RTL原型：投影/比较PE、排序网络、alpha和混合核心。",
        "在相同约束下比较周期、带宽、面积、频率与能效。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2.2 应当完成", 2)
    for item in (
        "块级透射率终止掩码与跨阶段条件跳过。",
        "2至4种粗粒度资源配置及轻量负载统计。",
        "形状与不透明度感知的有效像素块跳过。",
        "消融实验和设计参数敏感度分析。",
    ):
        add_bullet(doc, item)
    add_heading(doc, "2.3 可选扩展", 2)
    add_body(doc, "SH参数压缩、连续帧复用、完整1080p实时上板和全资源池化不作为论文核心交付条件，只有在主线完成后推进。")

    add_heading(doc, "3. 系统基线定义", 1)
    add_heading(doc, "3.1 数据流 v0.1", 2)
    steps = (
        "深度预处理和视锥剔除。",
        "从近到远执行全局深度粗分组。",
        "对当前组执行2D位置与协方差投影和屏幕剔除。",
        "对组内有效高斯进行稳定精确排序。",
        "按高斯顺序生成有效像素块，计算SH、alpha并更新颜色与透射率。",
        "用像素/块级终止状态控制后续计算和数据读取。",
    )
    for step in steps:
        add_number(doc, step)

    add_heading(doc, "3.2 B0与R0", 2)
    add_table(
        doc,
        ["维度", "固定功能 B0", "可重构 R0"],
        [
            ("计算资源", "投影、排序、SH、alpha/混合独立", "保留专用单元，并设置共享弹性PE"),
            ("调度", "资源数量固定", "仅在高斯组或子图边界切换配置"),
            ("目标", "提供稳定、易验证的比较基线", "提高跨场景平均利用率和能效"),
            ("主要风险", "资源在非瓶颈阶段闲置", "互连、切换和时序成本抵消复用收益"),
        ],
        [1800, 3780, 3780],
        keep_together=True,
    )

    add_heading(doc, "4. 正确性约束", 1)
    invariants = (
        "每个像素的混合次序必须与参考深度序列一致。",
        "深度组间保持全序；深度相等时用Gaussian ID作为稳定次关键字。",
        "提前终止是逐像素状态，不能用单个像素或单个块的终止替代全局终止。",
        "允许多高斯流水并行，但同一像素块必须按顺序提交状态更新。",
        "精确模式的形状跳过不得产生假阴性；近似模式必须计入画质预算。",
        "软件模型与RTL使用完全一致的舍入、饱和、阈值和指数近似。",
    )
    for item in invariants:
        add_bullet(doc, item)
    add_callout(doc, "重要决策", "第一版不采用逐周期全资源重构，而采用组/子图边界的粗粒度配置切换；保留阶段专用核心，降低调度和互连风险。", fill=LIGHT_GREEN)

    add_heading(doc, "5. 验收指标", 1)
    add_table(
        doc,
        ["类别", "指标", "v0.1验收原则"],
        [
            ("正确性", "排序序列、参与混合集合、逐像素RGB/T", "精确模式与FP32参考一致；RTL逐事务匹配定点模型"),
            ("画质", "PSNR、SSIM、LPIPS", "近似优化单独报告；初始目标PSNR下降不超过0.2 dB"),
            ("性能", "cycle/frame、FPS、停顿周期、PE利用率", "跨场景报告几何平均，不用单场景峰值代替"),
            ("存储", "DRAM/SRAM字节数、队列高水位", "属性延迟读取，并分解每阶段流量"),
            ("硬件", "面积、频率、功耗、mJ/frame", "B0与R0使用相同器件、带宽、精度和面积约束"),
        ],
        [1320, 2700, 5340],
    )

    add_heading(doc, "6. 风险台账", 1)
    add_table(
        doc,
        ["风险", "等级", "当前控制措施"],
        [
            ("Gaussian-wise混合产生块访问冲突和停顿", "高", "使用块级scoreboard；先测量冲突率再定阵列规模"),
            ("统一MAC/比较PE互连过重、频率下降", "高", "始终与独立阵列基线比较；仅共享适合迁移的资源"),
            ("提前终止被错误扩大为全局终止", "高", "维护pixel/block T-mask；仅全子图终止时跳过后续组"),
            ("动态调度停留在概念，缺乏规则", "中", "先离线标定2至4种配置并用LUT选择"),
            ("研究范围过大影响交付", "高", "三级范围管理；参数压缩和完整上板设为扩展"),
            ("环境和数据集尚未配置", "中", "先用Python合成小场景完成算法与周期验证"),
        ],
        [3180, 1080, 5100],
        [WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT],
    )

    add_heading(doc, "7. 下一阶段任务", 1)
    add_callout(doc, "阶段目标", "编译验证alpha/blend RTL并继续投影、排序、DMA；建立整图PSNR、SSIM、LPIPS；工艺环境就绪后完成具体节点PPA。", fill=LIGHT_AMBER, label_color=RED)
    next_tasks = [
        ("N1", "实现流接口RTL骨架", "ready/valid寄存切片、skid buffer和断言", "已完成"),
        ("N2", "实现配置与计数器", "shadow/active commit、epoch和64位计数器", "已完成"),
        ("N3", "实现两级终止链路", "像素mask、首次全终止脉冲、粗表写回", "已完成"),
        ("N4", "执行ASIC综合标定", "面积、频率、功耗、启动间隔和资源权重", "待工具/工艺"),
        ("N5", "完成定点与画质链路", "Cholesky alpha；PSNR/SSIM/LPIPS逐图评价", "alpha完成"),
    ]
    add_table(doc, ["编号", "任务", "验收输出", "状态"], next_tasks, [720, 2640, 4800, 1200], [WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.CENTER])

    add_heading(doc, "8. 工作记录", 1)
    add_heading(doc, "2026-08-03｜建立研究基线", 2)
    for item in (
        "完整阅读开题报告，并与GSCore、GCC和综述的架构思路交叉核对。",
        "确定课题核心为Gaussian-wise数据流下的粗粒度动态资源配置，而非单纯复现GCC。",
        "建立本地工作区结构，以及《系统规格_v0.1.md》。",
        "定义固定功能B0和可重构R0，冻结第一版正确性不变量与验收指标。",
        "识别提前终止、混合冲突、统一PE互连和研究范围四项首要风险。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-03｜FP32黄金模型首版", 2)
    for item in (
        "实现3D协方差、透视投影、0至3阶实球谐、alpha与前向混合数学原语。",
        "同时实现独立pixel-wise参考和Gaussian-wise块级遍历，用前者校验后者。",
        "加入稳定深度排序、深度分组、逐像素透射率、提前终止和执行统计。",
        "完成7项定向测试，两个执行模式的RGB、T、终止掩码和贡献集合均一致。",
        "明确当前分组仍为功能级精确实现，硬件式粗分组和块级scoreboard进入下一轮。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-03｜B0周期与流量模型首版", 2)
    for item in (
        "实现确定性的递归多枢轴深度分组，保证组容量、组间全序和等深度GID稳定次序。",
        "实现有限结果队列和块级scoreboard；允许块间交错混合，同块按前驱严格提交。",
        "建立B0流水模型，区分流水延迟与启动间隔，并统计阶段周期、队列停顿和逻辑数据流量。",
        "将精确逐像素alpha/T轨迹接入任务生成，只跳过已全部终止的块，保持提前终止语义正确。",
        "自动化测试扩展至21项，覆盖排序序列、提前终止收益、稀疏无冲突、单块热点和队列深度敏感性。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-03｜合成负载扫描", 2)
    add_table(
        doc,
        ["负载", "关键现象", "模型观察"],
        [
            ("稀疏分离", "块间无依赖", "0 scoreboard停顿；0队列背压"),
            ("多块密集", "块间交错隐藏依赖", "混合利用率约99.5%；瓶颈为队列/混合吞吐"),
            ("强遮挡", "逐像素T触发块跳过", "跳过46.3%候选块；配对实验周期减少42.3%"),
            ("单块热点", "所有任务竞争同一块", "503停顿周期；依赖额外441周期"),
        ],
        [1800, 3480, 4080],
    )
    add_callout(
        doc,
        "解释边界",
        "以上百分比来自96×96定向合成场景，只用于验证机制和定位瓶颈。当前FPS、周期和流量尚未由RTL或真实3DGS场景校准，不能作为最终硬件性能结论。",
        fill=LIGHT_AMBER,
        label_color=RED,
    )

    add_heading(doc, "2026-08-03｜R0动态可重构模型与架构筛选", 2)
    for item in (
        "抽取B0/R0共享任务图，统一排序ID、投影结果、块任务、逐像素终止语义和逻辑流量。",
        "定义8个抽象弹性资源额度及balanced、投影优先、排序优先和光栅优先4种配置。",
        "实现配置epoch、完全排空切换协议、显式切换开销和离线动态规划最优调度。",
        "发现并修正同一模式相邻组被错误排空的问题；修正后R0与B0差距由13%至458%缩小到0.5%至11.2%。",
        "自动化测试扩展至28项，覆盖工作图一致、公平额度、切换计费和同模式流水epoch。",
    ):
        add_bullet(doc, item)
    add_table(
        doc,
        ["负载", "动态R0选择", "相对最佳静态", "相对B0"],
        [
            ("稀疏分离", "全程排序优先", "0%", "+11.2%"),
            ("多块密集", "全程排序优先", "0%", "+0.9%"),
            ("强遮挡", "全程排序优先", "0%", "+0.5%"),
            ("单块热点", "全程投影优先", "0%", "+3.4%"),
        ],
        [2040, 2760, 2040, 2520],
    )
    add_callout(
        doc,
        "本轮负结论",
        "四类合成负载中动态R0均没有发生切换。固定blend阵列限制了alpha额度增加的收益，因此只池化投影、排序和alpha并不足以构成有效可重构架构。下一候选R1将评估alpha＋blend配对资源。",
        fill=LIGHT_GREEN,
    )

    add_heading(doc, "2026-08-03｜RTL工程规范建立", 2)
    for item in (
        "内部流接口采用ready/valid握手与AXI4-Stream风格背压语义，存储和控制分别参考AXI4及APB/AXI4-Lite风格。",
        "规定shadow/active配置、组/epoch边界原子commit、排空协议和配置版本隔离。",
        "补充可综合SystemVerilog、显式位宽、复位、CDC、FIFO/scoreboard死锁和断言要求。",
        "要求lint、CDC、综合、setup/hold时序和同工具同约束公平比较；抽象额度在综合前不得称为等面积。",
        "规定输入等待、背压、队列满、依赖停顿、重配置及数据流量等可观测计数器。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-03｜R1配对光栅资源模型", 2)
    for item in (
        "将alpha入口、blend提交口和结果队列容量组成配对光栅通道，消除R0只扩alpha的吞吐断点。",
        "引入暂定面积额度：投影2、排序1、配对光栅2；四种模式均严格使用12额度。",
        "复用共享任务图、scoreboard和epoch动态规划，保持排序、提前终止与流量语义不变。",
        "自动化测试扩展至35项，新增面积预算、配对通道、异质阶段切换和高开销抑制检查。",
        "建立ADR-001，正式停止把R0作为最终候选，并将R1保留为下一阶段验证对象。",
    ):
        add_bullet(doc, item)
    add_table(
        doc,
        ["负载", "B0周期", "R0周期", "R1周期 / 模式", "R1相对B0"],
        [
            ("稀疏分离", "125", "139", "139 / 均衡", "+11.2%"),
            ("多块密集", "2692", "2717", "2070 / 光栅优先", "-23.1%"),
            ("强遮挡", "4486", "4508", "3420 / 光栅优先", "-23.8%"),
            ("单块热点", "386", "399", "385 / 投影优先", "-0.3%"),
        ],
        [1680, 1200, 1200, 3360, 1920],
    )
    add_callout(
        doc,
        "机制结论",
        "R1在密集与强遮挡合成负载中消除了固定blend瓶颈，但普通四类负载仍各自使用单一静态模式。模型周期改善不能在暂定面积额度下解释为等面积硬件加速。",
        fill=LIGHT_GREEN,
    )

    add_heading(doc, "2026-08-03｜异质阶段调度器定向验证", 2)
    for item in (
        "构造前段投影后全剔除、后段高块覆盖的非代表性场景，仅用于验证调度器切换能力。",
        "默认12周期切换开销下选择投影优先→光栅优先，总周期944；最佳静态模式979周期，减少3.6%。",
        "切换开销为24周期时仍切换；升至48周期后自动改为全程光栅优先且不切换。",
        "该结果证明epoch划分和切换计费正确，不代表真实3DGS场景存在3.6%的动态收益。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜真实3DGS数据接入", 2)
    for item in (
        "审计data目录下13个训练完成场景，统一使用iteration 30000；最终模型合计39,781,233个高斯。",
        "确认PLY均为二进制小端62个FP32字段，正确执行opacity sigmoid、scale exp、四元数归一化和SH重排。",
        "实现内存映射与分批导入，避免复制约15.6 GiB原始数据；完成相机world-to-camera转换和等视场缩放。",
        "新增4项数据导入测试，总自动化测试增至39项并全部通过。",
        "生成real_scene_inventory.json，记录场景规模、相机数、分辨率和抽样属性分布。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜39视角真实候选块负载分析", 2)
    for item in (
        "每场景选取首、中、末三个相机，统一将最长边缩放到1920像素，共分析39个真实视角。",
        "对完整高斯集合执行向量化深度、3D协方差投影、屏幕剔除和8×8候选块统计。",
        "39个视角的最佳固定配置全部为光栅优先，进一步支持alpha＋blend配对的R1结构。",
        "动态相对最佳固定模式的候选周期几何平均减少约1.23%；11个视角超过1%，9个超过2%，最大约7.71%。",
        "5个视角完全不切换；当前统计未计入逐像素提前终止、SRAM冲突和ASIC重配置PPA成本。",
    ):
        add_bullet(doc, item)
    add_table(
        doc,
        ["真实负载指标", "结果", "当前解释"],
        [
            ("最终高斯总数", "3978万", "单场景约102万至613万"),
            ("抽样视角", "13场景 / 39视角", "每场景首、中、末三个相机"),
            ("最佳固定模式", "39/39光栅优先", "候选块处理是主要瓶颈"),
            ("动态几何平均", "周期减少约1.23%", "收益偏小，需ASIC PPA复核"),
            ("超过2%收益", "9/39视角", "存在局部模式变化，但不普遍"),
        ],
        [2700, 2100, 4560],
    )
    add_callout(
        doc,
        "ASIC架构决策",
        "主候选收敛为光栅优先R1，并保留低频粗粒度配置能力。暂不实现复杂逐组动态互连；只有精确提前终止轨迹和ASIC PPA仍证明净收益时，才升级为帧内动态主方案。",
        fill=LIGHT_GREEN,
    )

    add_heading(doc, "2026-08-04｜ASIC评价边界", 2)
    for item in (
        "后续公平比较统一使用相同工艺节点、标准单元库、SRAM宏、PVT角、数值格式和带宽上限。",
        "面积区分组合逻辑、触发器、SRAM宏和时钟网络；时序报告WNS/TNS、关键路径和启动间隔。",
        "功耗区分动态、漏电、时钟、存储和片外IO，并报告能量/帧与有效块任务/焦耳。",
        "新增ADR-002：先实现固定光栅优先R1基线；动态调度作为可升级能力和设计空间消融。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜ASIC控制RTL骨架", 2)
    for item in (
        "实现ready/valid弹性寄存切片和两项skid buffer，支持任意下游背压并保持payload稳定。",
        "实现shadow/active安全提交、epoch递增、重复commit粘滞告警和64位饱和计数器快照。",
        "实现配对光栅通道控制壳，保留task、block、Gaussian和epoch标签；数值alpha/blend尚未接入。",
        "建立事务级等价模型和结构审计，总自动化测试由39项增至45项并全部通过。",
        "本机暂缺SystemVerilog仿真/综合器；RTL尚未完成真实编译、lint、SVA运行和ASIC PPA。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜代表场景精确alpha与提前终止轨迹", 2)
    add_table(
        doc,
        ["场景 / 视角", "ROI高斯", "活跃块比", "alpha计算比", "blend比"],
        [
            ("garden / 184", "38,866", "28.69%", "38.47%", "35.78%"),
            ("train / 150", "46,532", "2.70%", "4.67%", "8.12%"),
            ("bonsai / 291", "15,081", "7.64%", "9.98%", "12.54%"),
        ],
        [2160, 1680, 1800, 1800, 1920],
    )
    for item in (
        "对完整高斯集合执行真实相机投影，在最长边960、中心64×64 ROI内按深度和GID执行逐像素精确轨迹。",
        "与逻辑上完全禁用终止的对照相比，提前终止减少约61.5%至95.3%的alpha计算。",
        "三个ROI的4096个像素最终均达到T<1e-4，深层高斯任务可在属性读取和alpha发射前大量跳过。",
        "该结果不能外推为全帧加速比，但证明候选块数会明显高估真实光栅工作；新增ADR-003，将提前终止置于复杂动态互连之前。",
    ):
        add_bullet(doc, item)
    add_heading(doc, "2026-08-04｜bank化块终止状态RTL", 2)
    for item in (
        "新增4-bank终止表、单bank存储和光栅入口终止过滤器，并接入配对光栅通道。",
        "采用完整block tag与epoch匹配；容量碰撞只会少跳过，不会把未终止块误判为终止。",
        "查询为一周期ready/valid响应；同址终止写回采用写穿透，新状态立即可见。",
        "tag/epoch数据阵列不批量复位，只清valid sidecar，保留后续映射ASIC SRAM的可能。",
        "新增epoch清空、容量碰撞、写穿透和10000步随机轨迹测试，总测试增至51项并全部通过。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜3场景27个多位置精确ROI", 2)
    add_table(
        doc,
        ["场景", "alpha保留比范围", "中位数", "活跃块比中位数"],
        [
            ("garden", "38.07%～84.98%", "65.55%", "71.27%"),
            ("train", "4.67%～13.09%", "8.67%", "7.03%"),
            ("bonsai", "9.98%～22.50%", "16.15%", "13.15%"),
        ],
        [2160, 2760, 2160, 2280],
    )
    for item in (
        "每个视角在屏幕25%、50%、75%位置形成3×3网格，每个ROI为64×64像素，共27个精确轨迹。",
        "全部ROI的alpha保留比为4.67%至84.98%，中位数16.15%，证明中心区域不能代表整个屏幕。",
        "终止后暂定最佳固定模式为均衡19个、光栅优先7个、排序优先1个，不再是39/39光栅优先。",
        "暂定动态周期比几何平均约0.880，但仍受ROI抽样和未综合面积额度限制，不能称为ASIC净加速。",
        "新增ADR-004：主候选修订为终止感知的低频模式选择，复杂逐窗口动态互连继续暂缓。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜完整RTL与最终评价边界冻结", 2)
    for item in (
        "用户确认最终必须提交完整SystemVerilog RTL，不仅是关键模块；已建立从顶层、控制/DMA、存储、投影、排序、SH到alpha/blend、scoreboard和工艺适配的交付分解。",
        "图像质量评价冻结为PSNR、SSIM、LPIPS三项；已实现PSNR/SSIM和本地图像配对入口，LPIPS等待本地离线PyTorch、软件包和权重。",
        "最终必须在明确ASIC工艺节点、标准单元库、SRAM宏、PVT、频率和真实活动条件下报告面积与功耗；当前不使用抽象资源额度冒充PPA。",
        "新增ADR-005，把完整RTL、三项画质评价和具体节点PPA确立为不可删减的最终交付。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜像素终止层级与真实定点扫描", 2)
    add_table(
        doc,
        ["定点候选", "平均alpha误差", "阈值分类不一致", "结论"],
        [
            ("统一Q5.10 / conic 12小数", "0.2175", "33.72%", "否决"),
            ("共享二进制尺度 / conic 16小数", "0.0520", "7.77%", "仍不达标"),
        ],
        [3600, 1800, 2040, 1920],
    )
    for item in (
        "在garden、train、bonsai的9个64×64 ROI抽取900,000个真实Gaussian/像素样本，发现像素偏移最大约148,085，而二次型系数可极小，首版统一Q格式动态范围严重不足。",
        "每高斯共享二进制尺度把分类错误明显降低，但独立量化conic仍可能破坏半正定性；下一轮改为主轴或Cholesky因子表示后再决定alpha RTL。",
        "完成64位像素终止mask并接入配对光栅壳：blend侧新终止位单调OR，首次全1脉冲写入bank化块终止表。",
        "新增层级协议测试后，自动化回归增至65项并全部通过。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "2026-08-04｜保半正定alpha与blend RTL闭环", 2)
    add_table(
        doc,
        ["方案", "阈值分类不一致", "P99 alpha误差", "结论"],
        [
            ("统一Q格式", "33.72%", "约0.99", "否决"),
            ("单共享尺度", "7.77%", "约0.99", "否决"),
            ("Cholesky双指数块浮点", "0.186%", "0.01044", "首个RTL候选"),
        ],
        [3360, 2160, 1920, 1920],
    )
    for item in (
        "alpha改为Cholesky因子两项平方和，坐标与因子分别携带二进制指数；量化后仍保证二次型非负，避免宽整数conic乘法器。",
        "冻结首个面积均衡格式：delta Q5.10、Cholesky Q3.12、轴Q4.10、256项exp LUT、alpha Q1.12和T Q0.16；512项LUT保留为后续备选。",
        "新增alpha四级弹性流水、blend算术核、64×64 tile图像状态、保守读改写提交、APB寄存器、SRAM抽象wrapper和顶层集成子集。",
        "当前共有16个SystemVerilog模块、约1494行；自动化回归增至74项并全部通过。因本机无SV编译器，尚需真实编译、仿真和lint验证。",
        "新增ADR-006，正式记录保半正定Cholesky块浮点数值架构。",
    ):
        add_bullet(doc, item)

    add_heading(doc, "9. 文档维护规则", 1)
    add_body(doc, "本文件用于长期记录课题推进。每轮实质工作结束后更新首页状态、进展表、风险台账、下一阶段任务和工作记录。详细公式、接口和参数放入带版本号的系统规格；实验原始结果放入 experiments 目录。")
    add_body(doc, "保密要求：未经用户明确授权，不将开题报告、实现代码、实验数据、个人信息或本记录上传至网络、云盘、代码托管或其他公开平台。", bold_prefix="保密要求：")

    core = doc.core_properties
    core.title = "3DGS硬件加速器毕业设计工作进度记录"
    core.subject = "本地保密研究记录"
    core.author = ""
    core.keywords = "3DGS, 硬件加速器, 进度记录"

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build()
