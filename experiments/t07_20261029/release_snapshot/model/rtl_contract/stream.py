from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ElasticPipelineModel:
    """Transaction-level oracle for N register slices plus a two-entry skid FIFO."""

    stages: int = 4
    pipeline: list[int | None] = field(init=False)
    skid: list[int] = field(default_factory=list)

    def __post_init__(self):
        if self.stages <= 0:
            raise ValueError("stages must be positive")
        self.pipeline = [None] * self.stages

    def step(self, input_value: int | None, output_ready: bool) -> tuple[bool, int | None, bool]:
        output_value = self.skid[0] if self.skid else None
        output_valid = output_value is not None
        if output_valid and output_ready:
            self.skid.pop(0)

        downstream_ready = len(self.skid) < 2
        ready = [False] * self.stages
        for index in reversed(range(self.stages)):
            ready[index] = self.pipeline[index] is None or downstream_ready
            downstream_ready = ready[index]

        previous = self.pipeline.copy()
        if ready[-1] and previous[-1] is not None:
            self.skid.append(previous[-1])
        for index in reversed(range(1, self.stages)):
            if ready[index]:
                self.pipeline[index] = previous[index - 1]
        input_ready = ready[0]
        if input_ready:
            self.pipeline[0] = input_value
        return input_ready, output_value, output_valid


