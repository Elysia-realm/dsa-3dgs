"""Compute independent lower bounds from complete native baseline transactions."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t08_common import BASE, SCENES, read, save, sha


def main():
    frame_budget = 200_000_000 / 30
    rows = []
    for scene in SCENES:
        directory = BASE / 'diagnostic/native' / scene
        launch = read(directory / 'launch.json')
        log = directory / 'run.log'
        assert sha(log) == read(directory / 'run.execution.json')['log_sha256']
        result = directory / 'result.json'
        if not result.exists():
            assert 'real workload timed out' in log.read_text()
            rows.append(dict(scene=scene, resolution=[launch['width'], launch['height']], scope='TIMED_OUT',
                             log_sha256=sha(log), full_frame_floors=None))
            continue
        results = read(result)
        dma = results['counters']['REAL_DMA_COUNTS']
        independent = dict(qsu_read_port=dma['qsu_read_beats'], qsu_write_port=dma['qsu_write_beats'],
                           raster_shared_R=results['counters']['REAL_SHARED_PE']['R'])
        worst_floor = max(independent.values())
        assert worst_floor > frame_budget
        rows.append(dict(scene=scene, resolution=[launch['width'], launch['height']], scope='BASELINE_COMPLETE',
                         log_sha256=sha(log), full_frame_floors=independent,
                         multiple_of_frame_budget={k: v/frame_budget for k, v in independent.items()},
                         maximum_200mhz_fps_from_floors=200_000_000/worst_floor))
    save(BASE/'early_advance_20261120/native_floors.json', dict(status='BASELINE_SERVICE_BUDGET_FAIL',
         assumed_clock_mhz=200, target_fps=30, cycles_available_at_target=frame_budget,
         assumptions='Current single 128-bit beat per cycle on each QSU port, one R grant per cycle. '
                     'Each bound is independent and excludes contention, stalls and attribute DMA. '
                     'Work counts are from T07 native runs; this projects only changes that preserve those work counts.',
         results=rows, signed_off=False))
    for row in rows:
        print(row['scene'], row['scope'], row.get('multiple_of_frame_budget'), flush=True)


if __name__ == '__main__':
    main()
