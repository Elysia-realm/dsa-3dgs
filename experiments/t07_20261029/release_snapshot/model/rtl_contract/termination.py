from __future__ import annotations

from dataclasses import dataclass, field

from .pixel_mask import PixelTerminationMaskModel


@dataclass
class DirectMappedTerminationTableModel:
    """Oracle for the tag/epoch-protected banked termination table."""

    num_banks: int = 4
    rows_per_bank: int = 256
    entries: list[list[tuple[int, int] | None]] = field(init=False)

    def __post_init__(self):
        if self.num_banks <= 0 or self.num_banks & (self.num_banks - 1):
            raise ValueError("num_banks must be a positive power of two")
        if self.rows_per_bank <= 0 or self.rows_per_bank & (self.rows_per_bank - 1):
            raise ValueError("rows_per_bank must be a positive power of two")
        self.entries = [[None] * self.rows_per_bank for _ in range(self.num_banks)]

    @property
    def bank_bits(self) -> int:
        return (self.num_banks - 1).bit_length()

    def address(self, block_id: int) -> tuple[int, int]:
        bank = block_id & (self.num_banks - 1)
        row = (block_id >> self.bank_bits) & (self.rows_per_bank - 1)
        return bank, row

    def query(self, block_id: int, epoch_id: int) -> bool:
        bank, row = self.address(block_id)
        return self.entries[bank][row] == (block_id, epoch_id)

    def update(self, block_id: int, epoch_id: int) -> None:
        bank, row = self.address(block_id)
        self.entries[bank][row] = (block_id, epoch_id)

    def query_update_same_cycle(
        self,
        query_block_id: int,
        query_epoch_id: int,
        update_block_id: int,
        update_epoch_id: int,
    ) -> bool:
        write_through = (
            query_block_id == update_block_id and query_epoch_id == update_epoch_id
        )
        result = write_through or self.query(query_block_id, query_epoch_id)
        self.update(update_block_id, update_epoch_id)
        return result


@dataclass
class TerminationHierarchyModel:
    """Pixel mask to coarse block-table integration oracle."""

    mask_entries: int = 256
    num_banks: int = 4
    rows_per_bank: int = 256

    def __post_init__(self):
        self.pixel = PixelTerminationMaskModel(entries=self.mask_entries)
        self.block = DirectMappedTerminationTableModel(
            num_banks=self.num_banks, rows_per_bank=self.rows_per_bank
        )

    def update_pixels(self, block_id: int, epoch_id: int, new_mask: int) -> bool:
        pulse = self.pixel.update(block_id, epoch_id, new_mask)
        if pulse:
            self.block.update(block_id, epoch_id)
        return pulse

    def block_terminated(self, block_id: int, epoch_id: int) -> bool:
        return self.block.query(block_id, epoch_id)
