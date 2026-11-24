"""Cycle and data-movement models for candidate 3DGS architectures."""

from .b0 import B0Config, B0Report, simulate_b0
from .grouping import DepthRecord, GroupingReport, hierarchical_depth_groups
from .scoreboard import BlockTask, ScoreboardConfig, ScoreboardReport, simulate_scoreboard
from .r0 import DEFAULT_MODES, R0Config, R0GroupReport, R0Mode, R0Report, simulate_r0
from .workload import CycleWorkload, RasterTaskSpec, build_cycle_workload
from .r1 import (
    DEFAULT_R1_MODES,
    R1Config,
    R1EpochReport,
    R1Mode,
    R1Report,
    R1ResourceCosts,
    simulate_r1,
)

__all__ = [
    "B0Config",
    "B0Report",
    "simulate_b0",
    "DepthRecord",
    "GroupingReport",
    "hierarchical_depth_groups",
    "BlockTask",
    "ScoreboardConfig",
    "ScoreboardReport",
    "simulate_scoreboard",
    "R0Mode",
    "R0Config",
    "R0GroupReport",
    "R0Report",
    "DEFAULT_MODES",
    "simulate_r0",
    "RasterTaskSpec",
    "CycleWorkload",
    "build_cycle_workload",
    "R1ResourceCosts",
    "R1Mode",
    "R1Config",
    "R1EpochReport",
    "R1Report",
    "DEFAULT_R1_MODES",
    "simulate_r1",
]
