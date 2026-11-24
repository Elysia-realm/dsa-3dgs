#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <numeric>
#include <algorithm>
#include <vector>

namespace fs = std::filesystem;

struct IndexRecord { std::uint32_t gid; std::int32_t depth_q16; };

static std::uint64_t mask(unsigned width) {
    return width == 64 ? ~std::uint64_t{0} : ((std::uint64_t{1} << width) - 1);
}

static std::int64_t signed_code(float value, unsigned fractional, unsigned width) {
    const double scaled = static_cast<double>(value) * static_cast<double>(std::uint64_t{1} << fractional);
    auto code = static_cast<std::int64_t>(std::nearbyint(scaled));
    const auto lo = -(std::int64_t{1} << (width - 1));
    const auto hi = (std::int64_t{1} << (width - 1)) - 1;
    return std::min(std::max(code, lo), hi);
}

static std::uint64_t unsigned_code(float value, unsigned fractional, unsigned width) {
    const double scaled = static_cast<double>(value) * static_cast<double>(std::uint64_t{1} << fractional);
    auto code = static_cast<std::int64_t>(std::nearbyint(scaled));
    const auto hi = static_cast<std::int64_t>((std::uint64_t{1} << width) - 1);
    return static_cast<std::uint64_t>(std::min(std::max<std::int64_t>(code, 0), hi));
}

static std::uint64_t exp_unsigned_code(float raw_value, unsigned fractional, unsigned width) {
    // Follow the NumPy path: exp is first rounded to float32, then converted
    // to fixed point.  Host expf differs from NumPy by one ULP for a known
    // half-LSB case, so use the higher-precision result only to disambiguate
    // which side of that exact halfway point the mathematical value lies on.
    const double factor = static_cast<double>(std::uint64_t{1} << fractional);
    const float transformed = std::exp(raw_value);
    const double scaled = static_cast<double>(transformed) * factor;
    double rounded = std::nearbyint(scaled);
    const double lower = std::floor(scaled);
    if (scaled - lower == 0.5 && std::fmod(lower, 2.0) == 0.0) {
        const double precise_scaled = std::exp(static_cast<double>(raw_value)) * factor;
        if (precise_scaled > scaled) rounded = std::ceil(scaled);
    }
    auto code = static_cast<std::int64_t>(rounded);
    const auto hi = static_cast<std::int64_t>((std::uint64_t{1} << width) - 1);
    return static_cast<std::uint64_t>(std::min(std::max<std::int64_t>(code, 0), hi));
}

struct BitWriter {
    std::array<unsigned __int128, 9> beat{};
    unsigned offset = 0;
    void append(std::uint64_t value, unsigned width) {
        value &= mask(width);
        unsigned remaining = width;
        while (remaining) {
            const unsigned beat_index = offset / 128;
            const unsigned bit_index = offset % 128;
            const unsigned take = std::min(remaining, 128u - bit_index);
            const std::uint64_t part = value & mask(take);
            beat.at(beat_index) |= static_cast<unsigned __int128>(part) << bit_index;
            value >>= take;
            offset += take;
            remaining -= take;
        }
    }
};

static void write_u128(std::ostream& out, unsigned __int128 value) {
    const auto hi = static_cast<std::uint64_t>(value >> 64);
    const auto lo = static_cast<std::uint64_t>(value);
    out << std::hex << std::setfill('0') << std::setw(16) << hi << std::setw(16) << lo << '\n';
}

static std::uint64_t bits64(std::int64_t value) { return static_cast<std::uint64_t>(value); }

int main(int argc, char** argv) try {
    if (argc != 10) {
        std::cerr << "usage: build_batch PLY INDEX MEAN_STREAM OFFSET COUNT PIVOT0 PIVOT1 PIVOT2 OUTPUT\n";
        return 2;
    }
    std::cerr << "WARNING: non-signoff utility; host expf is not NumPy-bit-exact across all batches. "
                 "Use build_full_frame_rtl_batch.py for RTL qualification inputs.\n";
    const fs::path ply_path = argv[1], index_path = argv[2], mean_path = argv[3], output = argv[9];
    const std::uint64_t offset = std::stoull(argv[4]);
    const std::uint32_t count = static_cast<std::uint32_t>(std::stoul(argv[5]));
    const std::array<std::int32_t, 3> pivots = {
        std::stoi(argv[6]), std::stoi(argv[7]), std::stoi(argv[8])
    };
    fs::create_directories(output);

    std::ifstream ply(ply_path, std::ios::binary);
    if (!ply) throw std::runtime_error("cannot open PLY");
    std::string line;
    std::uint64_t vertex_count = 0;
    unsigned properties = 0;
    bool in_vertex = false;
    while (std::getline(ply, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.rfind("element ", 0) == 0) {
            std::istringstream stream(line);
            std::string element, name;
            stream >> element >> name;
            in_vertex = name == "vertex";
            if (in_vertex) stream >> vertex_count;
        } else if (in_vertex && line.rfind("property ", 0) == 0) {
            ++properties;
        } else if (line == "end_header") break;
    }
    const auto ply_data_offset = static_cast<std::uint64_t>(ply.tellg());
    if (properties != 62) throw std::runtime_error("expected 62 float vertex properties");
    const std::uint64_t record_bytes = properties * sizeof(float);

    std::ifstream index(index_path, std::ios::binary);
    index.seekg(static_cast<std::streamoff>(offset * sizeof(IndexRecord)));
    std::vector<IndexRecord> records(count);
    index.read(reinterpret_cast<char*>(records.data()), static_cast<std::streamsize>(records.size() * sizeof(IndexRecord)));
    if (!index) throw std::runtime_error("cannot read index slice");

    // Preserve depth-stream order in the outputs while reading records in
    // monotonically increasing GID order.  The PLY is on local storage and
    // selected records are sparse, so direct monotonic reads avoid scanning
    // the entire multi-hundred-MiB file for every generated batch.
    std::vector<std::array<float, 62>> selected(count);
    std::vector<std::size_t> read_order(count);
    std::iota(read_order.begin(), read_order.end(), 0);
    std::sort(read_order.begin(), read_order.end(), [&](std::size_t lhs, std::size_t rhs) {
        return records[lhs].gid < records[rhs].gid;
    });
    for (const auto slot : read_order)
        if (records[slot].gid >= vertex_count) throw std::runtime_error("GID exceeds PLY vertex count");
    for (const auto slot : read_order) {
        const auto byte_offset = ply_data_offset
                               + static_cast<std::uint64_t>(records[slot].gid) * record_bytes;
        ply.seekg(static_cast<std::streamoff>(byte_offset));
        ply.read(reinterpret_cast<char*>(selected[slot].data()),
                 static_cast<std::streamsize>(record_bytes));
        if (!ply) throw std::runtime_error("cannot read selected PLY record");
    }

    std::ifstream mean(mean_path, std::ios::binary);
    mean.seekg(static_cast<std::streamoff>(offset * 16));
    // Binary mode suppresses Windows CRLF translation so files and hashes are
    // byte-for-byte identical to the qualified Python generator's LF output.
    std::ofstream mean_out(output / "mean.memh", std::ios::binary),
                  gid_out(output / "global_gid.memh", std::ios::binary),
                  attr_out(output / "attribute_sparse.memh", std::ios::binary),
                  camera_out(output / "camera.memh", std::ios::binary);
    if (!mean_out || !gid_out || !attr_out || !camera_out) throw std::runtime_error("cannot create output");
    for (std::size_t slot = 0; slot < records.size(); ++slot) {
        const auto& record = records[slot];
        std::uint64_t words[2]{};
        mean.read(reinterpret_cast<char*>(words), sizeof(words));
        if (!mean) throw std::runtime_error("cannot read mean record");
        mean_out << std::hex << std::setfill('0') << std::setw(16) << words[1] << std::setw(16) << words[0] << '\n';
        gid_out << std::hex << std::setfill('0') << std::setw(8) << record.gid << '\n';

        const auto& field = selected[slot];

        const std::array<float, 3> position = {field[0], field[1], field[2]};
        std::array<float, 4> quaternion = {field[58], field[59], field[60], field[61]};
        float norm2 = 0.0f;
        for (float value : quaternion) norm2 += value * value;
        const float norm = std::max(std::sqrt(norm2), 1.0e-12f);
        for (float& value : quaternion) value /= norm;
        const float raw_opacity = field[54];
        const float opacity = raw_opacity >= 0.0f
            ? 1.0f / (1.0f + std::exp(-raw_opacity))
            : std::exp(raw_opacity) / (1.0f + std::exp(raw_opacity));

        BitWriter writer;
        for (unsigned channel = 0; channel < 3; ++channel) {
            writer.append(static_cast<std::uint64_t>(signed_code(field[6 + channel], 12, 18)), 18);
            for (unsigned basis = 1; basis < 16; ++basis) {
                const auto property = 9 + channel * 15 + (basis - 1);
                writer.append(static_cast<std::uint64_t>(signed_code(field[property], 12, 18)), 18);
            }
        }
        writer.append(unsigned_code(opacity, 12, 13), 13);
        for (int i = 2; i >= 0; --i) writer.append(exp_unsigned_code(field[55 + i], 20, 24), 24);
        for (int i = 3; i >= 0; --i) writer.append(static_cast<std::uint64_t>(signed_code(quaternion[i], 20, 22)), 22);
        for (int i = 2; i >= 0; --i) writer.append(static_cast<std::uint64_t>(signed_code(position[i], 16, 27)), 27);
        if (writer.offset != 1118) throw std::runtime_error("attribute width mismatch");
        for (const auto beat : writer.beat) write_u128(attr_out, beat);
    }

    // Camera fixed words are invariant for this indexed Bonsai view.
    const std::array<std::int64_t, 22> fixed = {
        -155152,-664437,796218,317646,735934,676028,-987188,341227,92387,
        2765,-162664,260242,294691,31228,79842,4335147,4335147,2064384,1376256,
        13107,65536000,77
    };
    for (auto value : fixed) camera_out << std::hex << std::setfill('0') << std::setw(16) << bits64(value) << '\n';
    for (auto value : pivots) camera_out << std::hex << std::setfill('0') << std::setw(16) << bits64(value) << '\n';
    camera_out << "0000000000000040\n000000000000002b\n"
               << std::hex << std::setfill('0') << std::setw(16)
               << ((std::uint64_t{0x47534301} << 32) | count) << '\n';
    std::cout << "batch offset=" << offset << " count=" << count << " output=" << output.string() << '\n';
    return 0;
} catch (const std::exception& error) {
    std::cerr << "ERROR: " << error.what() << '\n';
    return 1;
}
