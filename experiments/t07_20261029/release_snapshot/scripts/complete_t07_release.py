"""Freeze and sign only the audited T07 functional/bounded-optimization scope."""
import sys,shutil,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,PROFILE,read,save,sha,run_logged,source_manifest
DATE='2026-10-31'
REPORT='docs/T07功能签核与性能交接_2026-10-31.md'
CHECKLIST='docs/毕业设计剩余任务执行清单_2026-09-20.md'
STATUS='verification/implementation_status.json'
LOG='docs/开发日志_2026-10-29_T07逐像素终止与形状验收.md'
NEW_PROFILE='verification/t07_release_profile.json'

def replace_once(s,old,new):
    assert s.count(old)==1,(old[:70],s.count(old));return s.replace(old,new,1)

def main():
    assert not (BASE/'signoff.json').exists(),'Existing release is immutable'
    a=read(BASE/'release_audit.json');assert a['status']=='PASS_T07_EVIDENCE'
    assert len(a['checks'])==8 and all(c['status']=='PASS' for c in a['checks'])
    production=source_manifest();state=read(ROOT/STATUS)
    assert state['t01_signed_off'] and state['t06_signed_off'] and not state['t07_signed_off']
    before=BASE/'closure_before';before.mkdir(exist_ok=False)
    changed=[STATUS,CHECKLIST,LOG,'AGENTS.md']
    for name in changed:
        target=before/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target)
    profile=read(PROFILE);profile.update(profile_id='t07_shape_pixel_v1',
      scope=a['acceptance_scope'],parent_profile='verification/t06_release_profile.json',
      frozen_source_manifest='experiments/t07_20261029/release_snapshot/manifest.json')
    profile['parameters'].update(ENABLE_SHAPE_BLOCK_REJECT=1,ENABLE_PIXEL_TERMINATION_SKIP=1)
    profile['numeric_contract']={'alpha_pass_min_q12':16,'alpha_max_q12':4055,'termination_max_q16':7,
      'color_q12_range':[0,4096],'RGB':'exact against same-input reference',
      'T':'exact unless both values <=7; terminal-T equivalence proved by zero rounded future RGB contribution',
      'epoch_scope':'Five nonempty repeated-frame scenes and observed-transition filter wrap tested; full-system tag recycling/backing-state initialization remains T11 work'}
    save(ROOT/NEW_PROFILE,profile)
    order=list(profile['scenes']);perf=sorted(a['full_performance'],key=lambda r:order.index(r['scene']))
    comparisons={r['scene']:r for r in a['comparisons']}
    mapping=read(BASE/'mapping/audit.json');shape=read(BASE/'shape_mapping/report.json')
    lines=['# T07功能签核与性能交接','',f'签核日期：{DATE}。正式配置：`t07_shape_pixel_v1`。',
      '**结论：T07在已冻结的功能、五场景宽128验证及有界成本取舍范围内完成签核。200MHz、最终面积/存储/功耗、目标分辨率GT与30FPS仍未通过。**','',
      '## 1. 实际改动与数值合同','',
      '- 正式配置启用已有保守形状块判定和精确低alpha跳过；新增逐像素终止过滤，在alpha发射前跳过已提交终止状态的像素。',
      '- 新过滤器使用256项完整block tag与64位掩码，别名保守放行，同拍更新透传；观察到epoch切换时仅清有效位，标签/掩码和payload不复位。候选路径不保留重复的旧粗/细终止逻辑，已在真实栅格模块综合结构中核验。',
      '- 生产顶层和各层参数已接通；通用默认仍兼容旧配置，后续构建必须显式应用新的release profile。没有用关闭候选的回归冒充候选验收。',
      '- RGB逐字节、非终止T与全局顺序严格一致。仅允许双方T均≤7的内部T差异；32448组T/alpha的独立整数界证明：合法颜色0..4096下，后续RGB舍入贡献恒为零，T不会增加。此规则不推广到其他颜色/阈值。',
      '- 本轮未改变QSU、BSU、共享G/P/R主路径或输入格式；未声称省去SH/属性读取。全系统epoch重用、空帧跨越完整代际空间及片外状态初始化不由滤波器局部回绕测试证明，保留T11责任。','',
      '## 2. 验收条件与证据','',
      '| 条件 | 当前证据与范围 |','|---|---|',
      '| 实际路径与数值 | 终止模块定向/随机、同拍更新、背压、别名、复位及观察到的epoch回绕通过；独立整数界32448组；形状RTL 20000向量与6940个被剔除行像素下界检查通过 |',
      '| 真实子集与消融 | B/S/P/C/A五种配置各五场景G/ideal，C另扩展至四模式×两AXI完整40次；合计60个不重复512记录运行 |',
      '| 五完整模型 | S/C各五场景G/legacy-ideal，原始完整集合，宽128；RGB DMA、PNG、排序、内部状态、完成/IRQ/事务排空、地址边界、独立浮点检查通过 |',
      '| 连续帧与恢复 | C五场景非空两帧E→自动选择；10类候选开关启用的控制/故障恢复；零opacity控制用例不替代真实非空功能证据 |',
      '| 已有能力 | 84次基础编译/83次基础执行、8组定向检查、独立投影/字段与生产lint、QSU存储端口/dot3资源检查通过 |',
      '| 全记录排序 | 复用T01五完整模型全记录QSU/BSU组件证据，4个实际编译源、参数、输入和ELF哈希匹配；T07生产可见记录排序另已重新运行 |',
      '| 成本与结构 | 两工艺TT各新旧终止结构映射/局部STA、形状模块面积映射，以及真实生产栅格模块结构检查；均非全芯片PPA签核 |',
      '| 可追溯性 | 8项统一审计通过，命令、工具/库、输入/源码/二进制/输出哈希、旧失败和新接受结果分开保存 |','',
      '子集中Bonsai/Counter/Train/Truck未触发逐像素终止，Room仅少量触发；明确作为低触发边界。五完整模型均有大量真实终止更新/跳过，不能仅根据开关置1判断路径执行。',
      '五张C完整模型成品已查看：可辨识场景结构，没有此前近似纯色异常；低分辨率细节不足保留，不以目视或内部浮点参考替代GT。','',
      '## 3. 完整模型同条件性能','',
      'B为冻结H基线；S只启用形状；C启用形状与逐像素终止，均保留精确alpha跳过。S/C使用同版源码、输入、工具及AXI模型，仅pixel开关不同。RTL计时为命令接受至最终RGB响应/DONE。','',
      '| 场景/相机 | Gaussian数 | 分辨率 | B周期 | S周期 | C周期 | C相对B减少 | pixel相对S减少 | 假定200MHz FPS | 浮点MAE |',
      '|---|---:|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in perf:
        c=comparisons[r['scene']]
        lines.append(f"| {r['scene']}/{r['camera']} | {r['gaussians']:,} | {r['width']}×{r['height']} | {c['baseline_cycles']:,} | {c['shape_only_cycles']:,} | {r['command_cycles']:,} | {r['saved_percent']:.3f}% | {c['pixel_incremental_saved_percent']:.3f}% | {200e6/r['command_cycles']:.3f} | {r['independent_float_mae']:.4f} |")
    lines += ['', '**上表频率是假定值，不是STA或实测硬件频率。** 五场景都未达到30FPS；目标分辨率与共享DDR条件还需另测。','',
      '| 场景 | pixel增量减少alpha任务 | pixel增量减少共享R服务 | C仿真墙钟秒 | C主机CPU秒 |',
      '|---|---:|---:|---:|---:|']
    for r in perf:
        c=comparisons[r['scene']];log=(BASE/'real/full/C'/r['scene']/'run.log').read_text()
        cpu=sum(float(x) for x in re.findall(r'(?:User|System) time \(seconds\):\s*([\d.]+)',log))
        lines.append(f"| {r['scene']} | {c['pixel_incremental_alpha_tasks_saved']:,} | {c['pixel_incremental_R_services_saved']:,} | {r['execution']['wall_seconds']:.2f} | {cpu:.2f} |")
    lines += ['', '主机墙钟/CPU包含仿真器装载与转储，不能算加速器收益。逐阶段busy/背压/等待、G/P/R争用、QSU划分/叶子、DMA事务及状态提交计数保留在release_audit.json的full_performance及原日志；重叠计数不相加。',
      '大量alpha/R工作被消除，但整帧增量仅约0.06%–0.19%，表明当前吞吐仍被前端/排序与供数限制。保留该模块的理由同时包括局部存储/面积收益，不继续扫掩码容量或阈值；T08优先减少实际属性字节和必要计算，随后执行强制服务率/DDR性能检查。','',
      '这些128宽图像只有144或176个8×8块，小于256项终止表容量。目标分辨率可能发生更多容量替换、损失跳过机会，不能外推本轮收益；完整tag及保守miss保证替换不会造成错误命中，功能边界另有定向测试。不得无预算地改成全帧驻留。','',
      '## 4. 局部面积与时序限制','',
      '| 工艺TT | 旧终止结构mm² | 新终止结构mm² | 局部面积减少 | 形状判定器mm² | 新setup WNS ns | 新hold WNS ns |',
      '|---|---:|---:|---:|---:|---:|---:|']
    for c in mapping['comparisons']:
        n=next(r for r in mapping['results'] if r['pdk']==c['pdk'] and r['pixel_skip']==1)
        sh=next(r for r in shape['results'] if r['pdk']==c['pdk'])
        lines.append(f"| {c['pdk']} | {c['old_area_mm2']:.6f} | {c['new_area_mm2']:.6f} | {c['saved_percent']:.2f}% | {sh['area_mm2']:.6f} | {n['setup_wns_ns']:.2f} | {n['hold_wns_ns']:.2f} |")
    lines += ['', '局部终止映射寄存位从79453减至25144，其中带复位位从1629减至276。此为同292位payload接口下的模块比较；不能从旧全芯片面积直接扣除该差额，亦不是SRAM宏面积。形状面积是单个组合判定器，不将ABC估计当顶层STA。',
      '真实栅格模块粗粒度结果为：旧513504个寄存位+13312个通用存储位，新434619+37888，合计减少54309位。新tag/mask分别为256×32及256×64，均为2读1写端口；这证明存储可被识别，不代表已有匹配SRAM宏。T11须按实际2R1W访问或经过验证的等效实现计入面积和时延，不能套用单读单写样例。',
      '局部hold、复位slew/cap仍有违例；ICsprout55新模块TT setup仅约0.04ns余量。没有进行T07全芯片三角PPA闭环，不能把正setup余量或更少复位位称作200MHz通过。原严重软复位分布问题仍归T11。','',
      '## 5. 失败闭环与停止决定','',
      '详见开发日志中的六项失败/修正：测试台握手等待、旧历史审计失效、scopeinfo元数据、连续帧误绑定旧顶层、Train终止T等价检查及结构检查的LUT处理顺序。错误输出/日志和修正前脚本保留，不笼统声称历史失败为零。',
      'Train S对照只有像素3684的T=4/2差异，RGB相同；两值均在原先冻结阈值内，未降低画质/排序要求。重检匹配的已完成运行不计为新仿真。LUT流程问题通过最小复现及真实生产模块重新检查闭环，没有setundef或排除未知硬件。',
      '接受C为正式配置，冻结T07并停止可选微调。T01/T06仍代表各自冻结版本，本轮物理结果仅限所列局部模块。','',
      '## 6. 下一步与保留责任','',
      '- 下一主任务T08：先建立五场景目标分辨率完整输入诊断及共同DDR/服务率预算，再实施版本化SH/协方差压缩和按需读取；不得把本轮1080p RGB DMA模块检查当成目标分辨率真实渲染。',
      '- T11前移：全芯片软复位/释放及在途AXI合同；检查现有APB单周期SOFT_RESET如何与忙时事务排空协调，不静默改成拒绝或延后。落实存储宏端口/延迟、总容量与算术面积预算，核验系统级epoch重用和片内/片外状态初始化。',
      '- T08后强制性能门槛保持；达不到则返回实测瓶颈任务，不能只靠T09策略拟合。T10保留13场景≥5视角的正式GT；T12保留200MHz、4mm²、300KB、1W、30FPS全部硬线。',
      '- 主入口仍为任务清单第2.3节和T01问题闭环计划；本轮只完成终止结构的一项局部资源改进，所有未验收全局问题继续OPEN。','',
      '当前问题台账为verification/physical_risk_register.json；只更新该工作台账，不覆写已冻结的T01问题记录。','',
      '## 7. 证据与重放入口','',
      '- 正式参数：verification/t07_release_profile.json；冻结源/脚本/报告：experiments/t07_20261029/release_snapshot/manifest.json。',
      '- 真实入口：scripts/run_t07_real.py（保留T06基线的B/S/P/C/A定义）；源、参数或输入不匹配时拒绝复用旧二进制。原生构建路径为/home/gs3d/work/t07_20261029。',
      '- 模块与回归：check_t07_units.py、check_t07_shape.py、run_t07_regressions.py；物理：map_t07_local.py、map_t07_shape.py、check_t07_production_structure.py。',
      '- 统一审计：scripts/audit_t07_release.py；正式签核：experiments/t07_20261029/signoff.json；完整性索引：accepted_artifacts.json。',
      '- release_audit.signed_off=false是审计生成器状态；最终签核以signoff.json和implementation_status.json为准。完整性检查用scripts/verify_t07_release.py，--current额外核对当前交接源码；后续版本使用冻结快照解释历史签核。',
      '- 接受的日志和输出保持不变；新的任务或重放须另建实验/构建目录。原Linux中间文件仍需保留；源码权威目录仍为D:\\3DGS。','']
    (ROOT/REPORT).write_text('\n'.join(lines),encoding='utf-8')
    text=(ROOT/CHECKLIST).read_text(encoding='utf-8')
    text=replace_once(text,
      '**当前下一执行项（2026-10-28更新）：T01已完成本轮接入与首次综合/STA反馈签核，下一主任务为T07。\nT11复位电气、存储与共享DDR预算配套前移；问题、解决方案和验收门槛见第2.3节。最终PPA与30FPS仍未通过。**',
      '**当前下一执行项（2026-10-31更新）：T07已按本轮功能/有界优化范围签核，下一主任务T08。\nT08先做目标分辨率真实诊断并落实共享DDR/资源预算，T11继续配套前移；最终PPA与30FPS未通过。**')
    text=replace_once(text,
      '| [ ] | T07 | 收敛形状感知、低 alpha 与提前终止 | 候选存在，正式配置及完整消融未验收 | 下一功能任务；接收2.2节T01恢复轮的WSL基线和资源/时序反馈后推进 |',
      '| [x] | T07 | 收敛形状感知、低 alpha 与提前终止 | t07_shape_pixel_v1：形状+逐像素终止，五完整模型、矩阵/连续帧及局部成本通过 | 2026-10-31功能签核；主任务转T08，最终GT/PPA/30FPS仍未通过 |')
    marker='### T08 — 参数压缩的最小完整实现'
    note='''#### 2026-10-31 T07签核与交接

正式配置t07_shape_pixel_v1。60次不重复子集、S/C各五完整模型、五场景非空连续帧，必要模块/恢复与8项审计通过。
五完整模型组合周期减少3.43%–7.01%；pixel相对shape-only仅增量减少约0.06%–0.19%，但局部终止结构面积减约60.6%，因此接受并停止继续微调。
RGB/排序严格一致，仅允许已证明双方T≤7的终止状态差异；来源和失败修正见《T07功能签核与性能交接_2026-10-31.md》。
本轮仅宽128与局部物理诊断，未通过最终质量/30FPS/PPA。下一项T08，不能继续用T06参数作为当前正式配置。
T08启动先完成五场景目标分辨率真实诊断、服务率及共享DDR预算；全芯片复位电气、存储/算术面积与代际状态重用合同由T11配套前移。

'''
    text=replace_once(text,marker,note+marker)
    text=replace_once(text,'T01与T06当前范围已签核；按第2.1/2.3节推进T07/T08及T11前移问题处理，T08后先过强制性能检查，再最终校准T09。',
      'T01/T06/T07当前范围已签核；本次从T08及T11前移问题处理推进，读取t07_release_profile，T08后先过强制性能检查，再最终校准T09。')
    text=replace_once(text,'下一项为 **T07**，按第2.1/2.3节推进；复位电气、面积/存储、共享DDR与最终硬指标仍按具体责任任务闭环。',
      'T07于2026-10-31完成功能与有界优化签核。下一项为 **T08**，继承t07_shape_pixel_v1；复位电气、面积/存储、共享DDR与最终硬指标仍按具体责任任务闭环。')
    (ROOT/CHECKLIST).write_text(text,encoding='utf-8')
    with (ROOT/LOG).open('a',encoding='utf-8') as f:f.write('\n## 2026-10-31最终签核\n\n生产结构检查按修正顺序完成，统一8项审计全部通过。T07按冻结功能及有界成本范围签核，正式配置t07_shape_pixel_v1；下一主任务T08。详见《T07功能签核与性能交接_2026-10-31.md》。最终GT、频率、面积、存储、功耗和30FPS未通过；原进行中及失败记录保留。\n')
    with (ROOT/'AGENTS.md').open('a',encoding='utf-8') as f:f.write('\n## 当前生产配置（2026-10-31）\n\nT07已按其功能范围签核，后续以`verification/t07_release_profile.json`的`t07_shape_pixel_v1`作为正式基线，不能用通用默认或T06旧参数替代。下一主任务T08；先开展目标分辨率真实诊断和共享DDR/资源预算。T11的全芯片复位/存储/代际状态初始化与T12最终PPA仍未关闭，详见T07签核交接报告及主清单。\n')
    state.update(planning_updated_at=DATE,t07_status='COMPLETE',t07_signed_off=True,t07_signoff_date=DATE,
      t07_signoff_scope=a['acceptance_scope'],t07_signoff_report=REPORT,t07_latest_log=REPORT,
      t07_release_profile=NEW_PROFILE,current_release_profile=NEW_PROFILE,
      physical_risk_register='verification/physical_risk_register.json',
      t07_release_audit='experiments/t07_20261029/release_audit.json',
      t07_signoff_record='experiments/t07_20261029/signoff.json',
      t07_shape_enabled=True,t07_pixel_termination_enabled=True,t07_alpha_zero_skip_enabled=True,
      t07_real_subset_runs=60,t07_full_model_runs=10,t07_full_model_scenes=5,t07_repeat_scenes=5,
      t07_full_chip_ppa_signed_off=False,t07_30fps_verified=False,t07_native_resolution_GT_signed_off=False,
      t07_next_task_handoff='T08 target-resolution diagnostic, compressed/conditional attribute supply; T11 reset/electrical, memory, shared DDR and system-wide epoch recycling contract.',
      next_execution_task='T08',next_functional_task='T08',
      t06_current_full_production_scope='Frozen t06_h_v1 functional evidence; superseded as active release by t07_shape_pixel_v1. T06 signoff retained for its own immutable snapshot.',
      t06_current_report_matches_current_rtl=False)
    save(ROOT/STATUS,state)
    try:
        run_logged([sys.executable,'-m','unittest','verification.test_implementation_status','-v'],BASE/'closure_checks.log')
        assert source_manifest()==production
    except BaseException:
        for name in changed:shutil.copy2(before/name,ROOT/name)
        raise
    # Frozen source package includes the actual compiler/testbench dependencies,
    # current helpers and selected project documents; no model/data duplication.
    files=set(production)|{REPORT,CHECKLIST,STATUS,LOG,NEW_PROFILE,'AGENTS.md',
       'docs/T07验收与有界优化计划_2026-10-29.md','docs/T01问题闭环与后续开发计划_2026-10-28.md',
       'verification/physical_risk_register.json'}
    for folder in ['rtl','scripts','asic/scripts','verification','model']:
        files.update(p.relative_to(ROOT).as_posix() for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.sv','.svh','.f','.py','.tcl','.cmd'])
    snap=BASE/'release_snapshot';assert not snap.exists()
    for name in sorted(files):
        p=snap/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,p)
    manifest={name:sha(snap/name) for name in sorted(files)};save(snap/'manifest.json',manifest)
    save(BASE/'visual_review.json',dict(status='REVIEWED',review_date='2026-10-29',archived_at=DATE,scenes=[dict(scene=r['scene'],png_sha256=sha(BASE/'real/full/C'/r['scene']/'frame.png')) for r in perf],
      finding='All five actual RTL-DMA PNGs inspected; scene structure visible, no previous near-flat-color defect. Low-resolution detail loss acknowledged; no GT/native-resolution claim.'))
    save(BASE/'signoff.json',dict(task='T07',date=DATE,status='COMPLETE',signed_off=True,scope=a['acceptance_scope'],
      audit_sha256=sha(BASE/'release_audit.json'),report=REPORT,report_sha256=sha(ROOT/REPORT),profile=NEW_PROFILE,profile_sha256=sha(ROOT/NEW_PROFILE),
      snapshot_manifest_sha256=sha(snap/'manifest.json'),decision=a['decision'],next_task='T08',
      final_ppa_pass=False,formal_GT_30FPS_pass=False,outstanding=a['outstanding']))
    evidence={}
    for name,h in read(BASE/'release_evidence_hashes.json').items():
        p=Path(name)
        try:relative=p.relative_to(ROOT).as_posix()
        except ValueError:relative=''
        target=snap/relative if relative in manifest else p
        evidence[str(target)]=h
    for name,h in manifest.items():evidence[str(snap/name)]=h
    for p in BASE.rglob('*'):
        if p.is_file() and p.suffix in ['.json','.log','.ys','.tcl','.constr','.script','.py','.sv'] and p.name not in ['accepted_artifacts.json','signoff_verification.json']:
            if p.name.endswith('_status.json') or p.name=='status.json':continue
            evidence[str(p)]=sha(p)
    save(BASE/'accepted_artifacts.json',dict(date=DATE,algorithm='SHA256',files=evidence,scope='Immutable T07 acceptance evidence; current working source paths rebased to release_snapshot where available. No self hash.'))
    print('SIGNED_OFF T07 functional scope; next T08; final PPA/GT/30FPS remain false',flush=True)
if __name__=='__main__':main()
