"""Algorithm oracle for staged odd-even sorting; not an RTL/PPA simulator."""
from __future__ import annotations


def sort_group(records: list[tuple], lanes: int, serial_fallback: bool = False,
               monotonic_fastpath: bool = False, stable_run_fastpath: bool = False) -> tuple[list[tuple], int]:
    if lanes < 1:
        raise ValueError("lanes must be positive")
    result = list(records)
    if monotonic_fastpath and lanes > 1:
        adjacent = list(zip(result, result[1:]))
        if all(a[:3] <= b[:3] for a, b in adjacent):
            return result, 0
        if all(a[:3] > b[:3] for a, b in adjacent):
            return list(reversed(result)), 0
        if stable_run_fastpath:
            prefix = result
            tail = []
            if result and all(a[:3] >= b[:3] for a, b in zip(result[:-1], result[1:-1])):
                prefix, tail = result[:-1], result[-1:]
            if all(a[:3] >= b[:3] for a, b in zip(prefix, prefix[1:])):
                runs = []
                for record in prefix:
                    if not runs or runs[-1][0][:3] != record[:3]:
                        runs.append([])
                    runs[-1].append(record)
                ordered = [record for run in reversed(runs) for record in run]
                if tail:
                    index = next((i for i, item in enumerate(ordered) if tail[0][:3] < item[:3]), len(ordered))
                    ordered.insert(index, tail[0])
                return ordered, 0
    if serial_fallback and lanes == 1:
        ordered = []
        for record in result:
            index = next((i for i, item in enumerate(ordered) if record[:3] < item[:3]), len(ordered))
            ordered.insert(index, record)
        return ordered, 0  # No odd/even phases on the streaming insertion path.
    previous_quiet = False
    phases = 0
    for phase in range(len(result)):
        swapped = False
        pairs = list(range(phase % 2, len(result) - 1, 2))
        for start in range(0, len(pairs), lanes):
            for left in pairs[start:start + lanes]:
                if result[left + 1][:3] < result[left][:3]:
                    result[left], result[left + 1] = result[left + 1], result[left]
                    swapped = True
        phases += 1
        if not swapped and previous_quiet:
            break
        previous_quiet = not swapped
    return result, phases
