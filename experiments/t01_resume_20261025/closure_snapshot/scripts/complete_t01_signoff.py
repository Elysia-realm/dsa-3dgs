"""One-shot T01 scope review record; does not claim timing or final PPA closure."""
import shutil, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t01_resume_common import BASE, read, save, sha, frozen, run_logged

REPORT = 'docs/T01恢复轮验收与物理风险交接_2026-10-28.md'
PLAN = 'docs/T01问题闭环与后续开发计划_2026-10-28.md'
CHECKLIST = 'docs/毕业设计剩余任务执行清单_2026-09-20.md'
STATUS = 'verification/implementation_status.json'
LOG = 'docs/开发日志_2026-10-25_T01恢复执行.md'
POLICY = 'docs/开发环境规范_WSL主路径_2026-10-24.md'
DATE = '2026-10-28'

def replace_once(text, old, new):
    assert text.count(old) == 1, ('expected one occurrence', old[:90], text.count(old))
    return text.replace(old, new, 1)

def main():
    assert not (BASE / 'signoff.json').exists(), 'Preserve an existing signoff; do not re-sign silently'
    sources = frozen()
    audit = read(BASE / 'final_audit.json')
    assert audit['status'] == 'PASS_T01_INITIAL_FEEDBACK_EVIDENCE'
    assert len(audit['checks']) == 10 and all(c['status'] == 'PASS' for c in audit['checks'])
    float_audit = read(BASE / 'fresh_float/audit.json')
    assert float_audit['status'] == 'PASS' and len(float_audit['results']) == 5
    assert all(r['reference_matches_previously_used'] and r['mae'] <= 5 for r in float_audit['results'])
    for f, h in float_audit['source_sha256'].items():
        assert sha(ROOT / f) == h.upper()
    snap = read(BASE / 'source_snapshot/manifest.json')
    for f, h in snap.items():
        assert sha(BASE / 'source_snapshot' / f) == h.upper()
        if f != 'AGENTS.md':
            assert sha(ROOT / f) == h.upper(), ('post-audit source drift', f)
    state = read(ROOT / STATUS)
    assert state['t01_signed_off'] is False and state['t06_signed_off'] is True
    assert state['next_execution_task'] == 'T01'
    mutable = [REPORT, PLAN, CHECKLIST, STATUS, LOG, POLICY, 'AGENTS.md', 'asic/README.md']
    backup = BASE / 'closure_before'
    assert not backup.exists(), 'Review prior closure attempt before retry'
    for f in mutable:
        p = backup / f
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f, p)
    shutil.copy2(BASE / 'signoff_package.json', backup / 'signoff_package.json')
    save(backup / 'manifest.json', {f: sha(ROOT / f) for f in mutable})

    # Manifest unifies this round's actual tools, target libraries and configuration.
    libs = []
    for pdk in ['nangate45', 'icsprout55']:
        m = read(BASE / 'synthesis/alpha1' / pdk / 'mapping.json')
        assert sha(Path(m['liberty'])) == m['liberty_sha256'].upper()
        libs.append(dict(pdk=pdk, corner='TT', path=m['liberty'], sha256=m['liberty_sha256']))
    save(BASE / 'accepted_toolchain_manifest.json', dict(tools=read(BASE / 'toolchain.json'),
        libraries=libs, production_profile=read(BASE / 'production_profile.json'),
        toolchain_record_sha256=sha(BASE / 'toolchain.json'),
        additional_corner_inventory='experiments/environment_setup_20261024/nangate_compatibility_audit.json',
        scope='Actual T01 TT runs; SS/FF inventory is not SS/FF execution evidence.'))
    save(BASE / 'comparison.json', dict(physical_matrix=audit['physical_matrix'],
        alpha_comparison=audit['alpha_comparison'], alpha_control=read(BASE / 'alpha_control/report.json'),
        final_ppa_pass=False, source_manifest_sha256=sha(BASE / 'frozen_source_manifest.json')))
    issues = [
      dict(id='T01-R1', owner='T11', priority='before timing-based architecture decisions during T07/T08',
           problem='Soft-reset distribution, slew/cap and recovery/removal violations'),
      dict(id='T01-R2', owner='T11', priority='resource budget alongside T07/T08',
           problem='Register-array area exceeds limit; macro ports/latencies and total storage budget pending'),
      dict(id='T01-R3', owner='T07/T08/T11', priority='mandatory post-T08 performance gate',
           problem='QSU/attribute/shared-service workload exceeds throughput budget; shared DDR model pending'),
      dict(id='T01-R4', owner='T12', priority='before final PPA signoff',
           problem='Valid data-path timing, all-corner electrical closure, frequency and activity power pending'),
      dict(id='T01-R5', owner='T10', priority='target-resolution diagnostics during T07/T08; full formal acceptance at T10',
           problem='Formal 13-scene multi-view resolution/GT/FPS coverage pending')]
    for issue in issues:
        issue.update(status='OPEN', plan=PLAN, closure_requires='Implementation and evidence against the corresponding row in plan section 2; not closed by T01 signoff')
    save(BASE / 'open_design_issues.json', dict(date=DATE, issues=issues, t00_contract_unchanged=True))

    text = (ROOT / REPORT).read_text(encoding='utf-8')
    text = replace_once(text, 'T01可按此范围签核；', 'T01已按此范围完成签核；')
    text += '''
## 8. 最终复核与签核记录（2026-10-28）

最终10项证据审计重新通过。另在WSL按本轮实际完整模型的相机、排序输入和原PLY重新生成
五场景浮点数学参考；解码RGB与此前使用的参考逐字节一致，RTL对拍MAE保持不变。
新旧PNG可能因编码字节不同而文件哈希不同，文件哈希与像素哈希分列；首次将PNG容器哈希
当像素等价的失败记录保留于fresh_float/initial_difference.json及原检查器快照。
该参考使用独立数学运算但共享输入量化/排序，不是GT，也不代替独立排序与原字段检查。

补充门禁：experiments/t01_resume_20261025/fresh_float/audit.json。
正式记录：experiments/t01_resume_20261025/signoff.json；证据冻结索引：accepted_artifacts.json。
原生成阶段的final_audit.signed_off=false和队列COMPLETE_PENDING_REVIEW保持其历史含义，
最终状态以本记录及implementation_status为准。原89项生产源和参数未改，T06既有签核不变。

已审查严重电气外推、寄存器面积超标、存储/DDR、频率、活动功耗和正式画质/帧率缺口。
解决路径、前移优先级和关闭条件写入《T01问题闭环与后续开发计划_2026-10-28.md》，
机器可读问题见open_design_issues.json，均保持OPEN。下一主任务T07，T11配套前移。
'''
    (ROOT / REPORT).write_text(text, encoding='utf-8')
    text = (ROOT / CHECKLIST).read_text(encoding='utf-8')
    text = replace_once(text,
      '**当前下一执行项（2026-10-24更新）：恢复T01，先迁移并验证WSL生产基线，再取得当前设计\n的首次可信综合/顶层STA反馈；具体范围、退出条件和T07交接见第2.2节。**',
      '**当前下一执行项（2026-10-28更新）：T01已完成本轮接入与首次综合/STA反馈签核，下一主任务为T07。\nT11复位电气、存储与共享DDR预算配套前移；问题、解决方案和验收门槛见第2.3节。最终PPA与30FPS仍未通过。**')
    text = replace_once(text,
      '| [ ] | T01 | 建立 ASIC 工具链并取得首次映射结果 | Linux STA/存储工具与双工艺三角库已配置；生产脚本迁移、Linux综合入口、缓存时序边界及顶层STA仍缺 | 当前下一执行项；按2.2节恢复，不等待解除Windows拦截；首次可信反馈后交接T07 |',
      '| [x] | T01 | 建立 ASIC 工具链并取得首次映射结果 | WSL五场景基线、双工艺TT四组映射/顶层STA与来源复核完成；严重物理违例已移交 | 2026-10-28按首次反馈范围签核；200MHz/面积/存储/功耗/30FPS未通过，见2.3节 |')
    text = replace_once(text, '### 2.2 当前下一步：恢复T01，再交接T07（2026-10-24综合评估）',
      '### 2.2 T01恢复轮原计划（2026-10-24制定，2026-10-28完成）\n\n以下保留执行前计划；当前完成状态及后续责任以第2.3节和最新签核记录为准。')
    text = replace_once(text,
      '4. Linux 工具冒烟已完成，生产回归脚本和综合流程的完整迁移仍待执行；Yosys/ABC 的 Linux\n   版本及映射入口须单独核实。每个后续任务先验证所需入口，再开展正式开发/验收。',
      '4. 2026-10-28已验证T01/T06本轮所需的WSL生产回归与Linux Yosys/ABC映射/顶层STA入口。\n   旧Windows启动器未全部迁移；后续任务仍先检查并验证新增所需入口，再开展正式开发/验收。')
    text = replace_once(text, '### T01 — ASIC 工具链与首次映射',
      '### T01 — ASIC 工具链与首次映射\n\n**最新状态（2026-10-28）：按第2.2节首次反馈范围完成签核。** 具体证据、限制和问题交接见第2.3节及《T01恢复轮验收与物理风险交接_2026-10-28.md》；下方旧断点记录原样保留。')
    section = '''### 2.3 T01签核与问题处理计划（2026-10-28）

T01本轮已签核：40次真实子集、五完整模型、五场景连续帧/全记录排序及必要边界检查通过；
双工艺TT×alpha开关四组完整映射/生产顶层STA完成，10项审计和新生成五场景浮点参考复核通过。
生产RTL不变。签核范围为WSL接入及首次物理风险反馈，不能称200MHz或最终PPA通过。
此前“等待STA环境”“尚未执行顶层STA”等段落保留为历史记录，不代表当前状态。

执行方案见[《T01问题闭环与后续开发计划》](T01问题闭环与后续开发计划_2026-10-28.md)，
本节及各任务条目引用它作为后续开发要求。该计划列出具体候选、试验边界、通过门槛和失败处理。

| 后续任务 | 本轮新增的必需处理 |
|---|---|
| T07 | 继承WSL基线；按形状/低alpha/提前终止消融，验证跳过实际减少前端工作或流量；五场景和已有功能保持覆盖 |
| T11配套前移 | 先核对软复位事务/释放合同，处理高扇出slew/cap及恢复撤除；建立全部存储/端口台账与SRAM替换验证；校准共享DDR |
| T08 | 版本化SH/协方差压缩及按需读取，测总线实际字节、解码开销、画质和整帧周期 |
| T08后检查 | 目标分辨率五场景诊断与服务率/带宽预算；仍不满足时返回具体瓶颈任务，不能用策略调参掩盖吞吐缺口 |
| T10/T12 | 13场景≥5视角正式质量与帧率；冻结版本双工艺SS/TT/FF、200MHz、4mm²、300KB、1W闭环，功耗未测不得称通过 |

软复位电气外推修复前不根据当前WNS推算Fmax；寄存器方案23.85/34.21mm²不代表SRAM实现
必然达标；宽128假定200MHz的3.52–5.86FPS不代表目标分辨率。所有问题保持OPEN，
见experiments/t01_resume_20261025/open_design_issues.json；关闭必须有新版本实现与验证证据。

签核报告：[T01恢复轮验收与物理风险交接](T01恢复轮验收与物理风险交接_2026-10-28.md)。
正式签核记录：experiments/t01_resume_20261025/signoff.json。下一主任务T07；本轮未启动T07 RTL开发。

'''
    text = replace_once(text, '## 3. 各任务的交付与验收', section + '## 3. 各任务的交付与验收')
    for task, title in [('T07','形状感知与提前终止收敛'),('T08','参数压缩的最小完整实现'),
                        ('T10','完整场景与画质'),('T11','ASIC 存储建模与综合前收敛'),('T12','双工艺综合级 ASIC PPA')]:
        heading = f'### {task} — {title}'
        text = replace_once(text, heading, heading + '\n\n2026-10-28补充：执行第2.3节及《T01问题闭环与后续开发计划》对应行；相关问题在新证据完成前保持OPEN。')
    text = replace_once(text,
      '按第2.1节执行T06收尾、T07/T08及前移验证；T08后先过强制性能检查，再最终校准T09。',
      'T01与T06当前范围已签核；按第2.1/2.3节推进T07/T08及T11前移问题处理，T08后先过强制性能检查，再最终校准T09。')
    text = replace_once(text,
      '不代表30FPS/GT/PPA通过。下一项为 **T07**，按第2.1节路线推进；T01 继续保留断点，等待用户补 STA\n环境/其他工具，其方框不因后续功能任务完成而勾选。',
      '不代表30FPS/GT/PPA通过。T01于2026-10-28完成WSL接入与首次综合/顶层STA反馈签核。\n下一项为 **T07**，按第2.1/2.3节推进；复位电气、面积/存储、共享DDR与最终硬指标仍按具体责任任务闭环。')
    (ROOT / CHECKLIST).write_text(text, encoding='utf-8')
    text = (ROOT / 'AGENTS.md').read_text(encoding='utf-8')
    text = replace_once(text,
      '- 当前仅已完成 Linux 工具环境验证，现有生产回归脚本与综合流程的完整迁移尚未完成。\n  后续任务先完成其所需入口的迁移和验证，再执行正式工作；不新建主任务、不缩减五场景及\n  T10 正式验收范围，不因此改变任何任务签核状态。',
      '- 2026-10-28已完成T01/T06本轮所需生产验证入口的WSL迁移、五场景复现与双工艺TT综合/顶层STA。\n  旧Windows启动器尚未全部迁移；后续任务仍先检查其所需入口并在Linux重建。T01仅签核首次反馈，\n  最终时序/电气/面积/存储/功耗/30FPS未通过；按`docs/T01问题闭环与后续开发计划_2026-10-28.md`\n  将复位电气、存储和DDR预算前移配套T07/T08。不得缩减五场景或T10正式验收范围。')
    (ROOT / 'AGENTS.md').write_text(text, encoding='utf-8')
    with (ROOT / POLICY).open('a', encoding='utf-8') as f:
        f.write('\n## 2026-10-28执行状态更新\n\nT01所需WSL生产回归、综合及生产顶层STA已完成并按首次反馈范围签核。旧Windows启动器未全部迁移；未来新增入口仍须检查、Linux重建并验证。系统保护保持不变。最终PPA与30FPS未通过，具体范围与后续责任见T01恢复轮验收与物理风险交接及问题闭环计划（2026-10-28）。上述2026-10-24状态保留为历史。\n')
    with (ROOT / LOG).open('a', encoding='utf-8') as f:
        f.write('\n## 2026-10-28最终复核与签核\n\n五场景真实迁移验证与四组双工艺TT映射/生产顶层STA全部完成；最终10项审计重新通过。独立浮点参考用实际输入重新生成五场景，解码RGB均与历史参考逐字节一致，MAE不变；PNG文件编码差异及早期检查失败保留。无生产RTL修改。\n\nT01按首次接入/物理反馈范围完成签核，详见《T01恢复轮验收与物理风险交接_2026-10-28.md》和experiments/t01_resume_20261025/signoff.json。200MHz、面积、存储、功耗、GT和30FPS未通过。严重复位电气外推、寄存器面积、存储/DDR与吞吐问题及具体处理门槛已写入《T01问题闭环与后续开发计划_2026-10-28.md》。下一主任务T07，T11配套前移；旧断点描述保留为历史。\n')
    text = (ROOT / 'asic/README.md').read_text(encoding='utf-8')
    text = replace_once(text, '# ASIC 实现入口（工艺无关阶段）', '# ASIC 综合与验证入口')
    text = replace_once(text, '## 2026-10-25 当前执行入口', '## 2026-10-28 当前执行入口')
    text = replace_once(text, 'T01正在WSL恢复，未签核。', 'T01已按WSL接入与首次物理反馈范围签核，最终时序/电气/PPA未通过。')
    text = replace_once(text, '本轮尝试保留原RTL全部控制和阵列并映射为标准单元，作为首次可信反馈；最终SRAM宏仍归T11。',
      '本轮已保留原RTL全部控制和阵列并映射为标准单元，四组双工艺TT顶层STA完成；最终SRAM宏仍归T11。\n验收与严重物理风险见`docs/T01恢复轮验收与物理风险交接_2026-10-28.md`，处理计划见`docs/T01问题闭环与后续开发计划_2026-10-28.md`。')
    (ROOT / 'asic/README.md').write_text(text, encoding='utf-8')

    state.update(planning_updated_at=DATE, next_execution_task='T07', next_functional_task='T07',
      t01_status='COMPLETE', t01_signed_off=True, t01_signoff_date=DATE,
      t01_signoff_scope=audit['acceptance_scope'], t01_signoff_report=REPORT, t01_latest_log=REPORT,
      t01_report=REPORT, t01_signoff_record='experiments/t01_resume_20261025/signoff.json',
      t01_toolchain_manifest='experiments/t01_resume_20261025/accepted_toolchain_manifest.json',
      t01_comparison_report='experiments/t01_resume_20261025/comparison.json',
      alpha_zero_skip_candidate_mapped_area_report='experiments/t01_resume_20261025/comparison.json',
      t01_sta_executed=True, t01_production_top_sta_executed=True, t01_cache_control_area_included=True,
      t01_blockers=[], t01_explicit_non_library_cells={}, t01_mapping_runs_complete=4,
      t01_last_mapping_source_matches_current_rtl=True, t01_evidence_integrity_pass=True,
      t01_evidence_integrity_scope='Frozen t06_h_v1: 89 production files and profile, source_snapshot; current only as of 2026-10-28 signoff',
      t01_evidence_audit='experiments/t01_resume_20261025/final_audit.json',
      t01_float_provenance_audit='experiments/t01_resume_20261025/fresh_float/audit.json',
      t01_200mhz_verified=False, t01_final_ppa_pass=False, t01_electrical_closure=False,
      t01_final_storage_budget_pass=False, t01_activity_power_verified=False,
      t01_final_area_pass=False, t01_final_30fps_pass=False,
      t01_open_design_issues='experiments/t01_resume_20261025/open_design_issues.json',
      t01_followup_plan=PLAN,
      t01_followup='T07 next; T11 reset/electrical, SRAM and shared-DDR work front-loaded alongside T07/T08. Mandatory post-T08 throughput gate; T10/T12 formal quality/PPA/FPS remain open.',
      t01_resume_note=REPORT,
      t01_historical_status_snapshot='experiments/t01_resume_20261025/closure_before/verification/implementation_status.json')
    state['execution_resume_plan'].update(status='COMPLETE', completed_at=DATE, report=REPORT)
    state['development_environment_policy'].update(
      production_script_migration_status='REQUIRED_T01_T06_ENTRIES_VALIDATED_NOT_ALL_LEGACY_LAUNCHERS_PORTED',
      linux_synthesis_flow_status='DUAL_PROCESS_TT_PRODUCTION_MAPPING_AND_TOP_STA_COMPLETE_INITIAL_FEEDBACK_ONLY')
    save(ROOT / STATUS, state)
    try:
        run_logged([sys.executable, '-m', 'unittest', 'verification.test_implementation_status',
                    'verification.test_t01_sta_structural', '-v'], BASE / 'closure_checks.log')
        assert frozen() == sources
    except BaseException:
        for f in mutable:
            shutil.copy2(backup / f, ROOT / f)
        raise

    supplement = sorted(set([*mutable, *float_audit['source_sha256'],
                             'scripts/complete_t01_signoff.py', 'scripts/verify_t01_signoff.py',
                             'verification/test_implementation_status.py']))
    dest = BASE / 'closure_snapshot'
    for f in supplement:
        target = dest / f
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / f, target)
    save(dest / 'manifest.json', {f: sha(dest / f) for f in supplement})
    package = read(BASE / 'signoff_package.json')
    package.update(status='SIGNED_OFF_INITIAL_FEEDBACK_ONLY', report_sha256=sha(ROOT / REPORT),
        final_audit_sha256=sha(BASE / 'final_audit.json'),
        float_audit_sha256=sha(BASE / 'fresh_float/audit.json'),
        closure_snapshot_manifest_sha256=sha(dest / 'manifest.json'))
    save(BASE / 'signoff_package.json', package)
    signoff = dict(task='T01', date=DATE, status='COMPLETE', signed_off=True,
        scope=audit['acceptance_scope'], source_manifest_sha256=sha(BASE / 'frozen_source_manifest.json'),
        production_profile_sha256=sha(BASE / 'production_profile.json'),
        report=REPORT, report_sha256=sha(ROOT / REPORT), final_audit_sha256=sha(BASE / 'final_audit.json'),
        independent_reference_audit_sha256=sha(BASE / 'fresh_float/audit.json'),
        source_snapshot_manifest_sha256=sha(BASE / 'source_snapshot/manifest.json'),
        closure_snapshot_manifest_sha256=sha(dest / 'manifest.json'),
        consistency_test_execution=read(BASE / 'closure_checks.execution.json'),
        review='Acceptance plan clauses 1-6 reviewed against the report; all required initial-feedback evidence present. Negative slack/electrical extrapolation explicitly retained as open design issues.',
        unresolved_design_issues='experiments/t01_resume_20261025/open_design_issues.json',
        followup_plan=PLAN, next_task='T07', timing_200MHz_pass=False, electrical_closure=False,
        final_area_storage_power_pass=False, formal_GT_30FPS_pass=False,
        stage_report_signed_off_false_is_historical_generator_state=True)
    save(BASE / 'signoff.json', signoff)
    # Hash immutable accepted copies plus original evidence files already verified by the final gate.
    evidence = dict(read(BASE / 'final_evidence_hashes.json'))
    selected = ['signoff.json', 'signoff_package.json', 'final_audit.json', 'final_evidence_hashes.json',
        'accepted_toolchain_manifest.json', 'comparison.json', 'open_design_issues.json',
        'migration_audit.json', 'closure_checks.log', 'closure_checks.command.json', 'closure_checks.execution.json']
    for folder in ['source_snapshot', 'closure_snapshot', 'closure_before', 'fresh_float']:
        selected += [p.relative_to(BASE).as_posix() for p in (BASE / folder).rglob('*') if p.is_file()]
    for f in selected:
        evidence[str(BASE / f)] = sha(BASE / f)
    # All these file paths are immutable acceptance evidence. Working documents live in closure_snapshot.
    save(BASE / 'accepted_artifacts.json', dict(date=DATE, algorithm='SHA256', files=evidence,
        note='Includes accepted evidence and source hashes. Future working-source changes are expected; use frozen snapshots to reproduce this signoff. No self hash.'))
    print('SIGNED_OFF T01 initial feedback only; next T07; all final PPA/FPS flags remain false', flush=True)

if __name__ == '__main__':
    main()
