from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ConfigEpochModel:
    mode_mask: int = 0x3
    epoch_mask: int = 0xFFFF
    shadow: int = 0
    active: int = 0
    epoch: int = 0
    pending: bool = False
    overrun: bool = False

    def step(
        self,
        *,
        shadow_write: int | None = None,
        commit: bool = False,
        epoch_boundary: bool = False,
        affected_empty: bool = False,
    ) -> bool:
        old_pending = self.pending
        if shadow_write is not None:
            self.shadow = shadow_write & self.mode_mask
        if commit and old_pending:
            self.overrun = True
        if commit:
            self.pending = True
        commit_pulse = (old_pending or commit) and epoch_boundary and affected_empty
        if commit_pulse:
            self.active = self.shadow
            self.epoch = (self.epoch + 1) & self.epoch_mask
            self.pending = False
        return commit_pulse


@dataclass
class SaturatingCounterBankModel:
    count: int = 8
    width: int = 64
    live: list[int] = field(init=False)
    snapshot: list[int] = field(init=False)

    def __post_init__(self):
        self.live = [0] * self.count
        self.snapshot = [0] * self.count

    def step(self, increments: list[bool], *, clear: bool = False, snapshot: bool = False) -> None:
        if len(increments) != self.count:
            raise ValueError("increment vector length mismatch")
        old = self.live.copy()
        maximum = (1 << self.width) - 1
        if clear:
            self.live = [0] * self.count
        else:
            self.live = [min(maximum, value + int(event)) for value, event in zip(self.live, increments)]
        if snapshot:
            self.snapshot = old

