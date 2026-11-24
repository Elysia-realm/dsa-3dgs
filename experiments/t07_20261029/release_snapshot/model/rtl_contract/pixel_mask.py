from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class PixelTerminationMaskModel:
    entries: int = 256
    pixels: int = 64
    state: list[tuple[int, int, int] | None] = field(init=False)

    def __post_init__(self):
        if self.entries <= 0 or self.entries & (self.entries - 1):
            raise ValueError("entries must be a positive power of two")
        if self.pixels <= 0:
            raise ValueError("pixels must be positive")
        self.state = [None] * self.entries

    @property
    def full_mask(self) -> int:
        return (1 << self.pixels) - 1

    def index(self, block_id: int) -> int:
        return block_id & (self.entries - 1)

    def query(self, block_id: int, epoch_id: int) -> int:
        entry = self.state[self.index(block_id)]
        if entry is None or entry[:2] != (block_id, epoch_id):
            return 0
        return entry[2]

    def update(self, block_id: int, epoch_id: int, new_terminated: int) -> bool:
        previous = self.query(block_id, epoch_id)
        merged = previous | (new_terminated & self.full_mask)
        self.state[self.index(block_id)] = (block_id, epoch_id, merged)
        return merged == self.full_mask and previous != self.full_mask

    def query_update_same_cycle(
        self, block_id: int, epoch_id: int, new_terminated: int
    ) -> tuple[int, bool]:
        pulse = self.update(block_id, epoch_id, new_terminated)
        return self.query(block_id, epoch_id), pulse
