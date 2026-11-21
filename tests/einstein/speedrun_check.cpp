// speedrun_check -- headless test harness for the Speed Run Einstein build.
//
// Links against Albert's SDL-free emulation core (ein_core.lib, from the
// einstein repository's emulator), boots the disc as Albert does, then runs
// a command script and prints key=value results for tests/einstein_check.py.
// (Modelled on the Wonder Boy port's tests/einstein/einstein_check.cpp.)
//
//   speedrun_check <mos.rom> <speedrun.dsk> <speedrun.sym> command...
//
// Commands, run in order:
//   boot NAME          run 7 s for XtalDOS to reach its prompt, type NAME and
//                      ENTER, run until the game's main loop (MainLoop: after
//                      the title screens; at most 120 s)
//   seconds S          run S emulated seconds
//   frames N           run N video frames
//   hold KEYS          hold game keys: comma list of UP,DOWN,LEFT,RIGHT,FIRE,PAUSE
//   release            release all keys
//   joy X Y FIRE       joystick 1: its axes (0-255, 128 at rest; Y 255 up), fire 1/0
//   peek8 SYM          print SYM=value (SYM may be NAME+OFFSET)
//   peek16 SYM
//   mem ADDR LEN       print mem_ADDR=hex (ADDR in hex)
//   vram ADDR LEN      print vram_ADDR=hex
//   shot FILE.ppm      save the picture (256x192)
//   record N PREFIX    run N frames, appending each picture to PREFIX.rgb and
//                      the AY's sound to PREFIX.wav (48 kHz)
//   rec_start PREFIX   record every frame from here, whatever runs, to rec_stop
//   rec_stop
//   type TEXT          type on the keyboard (a backslash-n: ENTER)
//   until SYM S        run until the PC reaches SYM (at most S seconds)
//   wait16 SYM VALUE   run until the word at SYM reaches VALUE; prints the
//                      TV frames it took (with -DFIXED_ELAPSED: a benchmark)
//   profile N          T-states per routine over N frames, the 80 costliest
//   profilel N         the same, local labels counted apart
//   fastpc N           run N frames: where VRAM writes came too fast
//   linehist SYM N     run N frames: the raster lines the PC reached SYM on
//   stats              VDP frames, fast VRAM accesses since the game began,
//                      interrupts, PC
//
// Symbols come from sjasmplus's --sym file ("Name: EQU 0x0000ABCD").

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#include "keyboard.h"
#include "machine.h"
#include "rom.h"
#include "tms9129.h"

namespace {

struct KeyPos { int row; int col; };

// The game's controls (src/einstein/keys.asm)
const std::map<std::string, KeyPos> kGameKeys = {
    {"RIGHT", {1, 2}},  // P
    {"LEFT", {1, 1}},   // O
    {"DOWN", {6, 6}},   // A
    {"UP", {5, 6}},     // Q
    {"FIRE", {0, 6}},   // SPACE
    {"PAUSE", {6, 1}},  // H
};

std::map<std::string, std::uint16_t> load_symbols(const char* path) {
    std::ifstream file(path);
    std::map<std::string, std::uint16_t> symbols;
    const std::regex entry("^([A-Za-z_][A-Za-z0-9_.@]*):\\s+EQU\\s+0x([0-9A-Fa-f]+)");
    std::string line;
    std::smatch m;
    while (std::getline(file, line))
        if (std::regex_search(line, m, entry))
            symbols[m[1]] = static_cast<std::uint16_t>(std::stoul(m[2], nullptr, 16) & 0xFFFF);
    return symbols;
}

KeyPos find_char(char ch) {
    if (ch == '\n') return {0, 5};  // ENTER
    for (int r = 0; r < 8; ++r)
        for (int c = 0; c < 8; ++c) {
            std::uint8_t code = ein::Keyboard::code(r, c, ein::Keyboard::kPlain);
            if (code >= 'a' && code <= 'z') code = std::uint8_t(code - 32);
            char want = ch;
            if (want >= 'a' && want <= 'z') want = char(want - 32);
            if (code == std::uint8_t(want)) return {r, c};
        }
    return {-1, -1};
}

// The PC at a program address: not while the MOS ROM is paged in over
// $0000-$1FFF, where its own code runs at the same addresses.
bool at_program_pc(const ein::Machine& m, std::uint16_t pc) {
    return m.cpu.pc.w == pc && (pc >= 0x2000 || !m.rom_enabled);
}

// While recording (rec_start), every new video frame is handed to it.
std::function<void()> g_on_frame;
std::uint64_t g_last_frame = 0;

void step(ein::Machine& m) {
    m.step();
    if (g_on_frame && m.vdp.frames() != g_last_frame) {
        g_last_frame = m.vdp.frames();
        g_on_frame();
    }
}

void run_tstates(ein::Machine& m, std::uint64_t count) {
    const std::uint64_t until = m.tstates + count;
    while (m.tstates < until) step(m);
}

void run_seconds(ein::Machine& m, double seconds) {
    run_tstates(m, std::uint64_t(seconds * ein::Machine::kCpuClockHz));
}

std::uint64_t g_fast_at_boot = 0;  // accesses made by MOS/XtalDOS before the game

void run_frames(ein::Machine& m, int frames) {
    const std::uint64_t target = m.vdp.frames() + std::uint64_t(frames);
    const std::uint64_t limit = m.tstates + std::uint64_t(frames + 2) * ein::Tms9129::kTStatesPerFrame;
    while (m.vdp.frames() < target && m.tstates < limit) step(m);
}

void type_text(ein::Machine& m, const std::string& text) {
    for (char ch : text) {
        const KeyPos k = find_char(ch);
        if (k.row < 0) { std::fprintf(stderr, "cannot type '%c'\n", ch); std::exit(2); }
        m.keyboard.set_key(k.row, k.col, true);
        run_seconds(m, 0.06);
        m.keyboard.set_key(k.row, k.col, false);
        run_seconds(m, 0.06);
    }
}

std::string hex_bytes(const std::vector<std::uint8_t>& bytes) {
    std::string out;
    char buf[4];
    for (std::uint8_t b : bytes) { std::snprintf(buf, sizeof buf, "%02X", b); out += buf; }
    return out;
}

void save_ppm(const ein::Machine& m, const std::string& path) {
    std::vector<std::uint32_t> frame(ein::Tms9129::kWidth * ein::Tms9129::kHeight);
    m.vdp.render(frame.data());
    std::ofstream out(path, std::ios::binary);
    out << "P6\n" << ein::Tms9129::kWidth << ' ' << ein::Tms9129::kHeight << "\n255\n";
    for (std::uint32_t pixel : frame) {
        const char rgb[3] = {char((pixel >> 16) & 0xff), char((pixel >> 8) & 0xff), char(pixel & 0xff)};
        out.write(rgb, 3);
    }
}

// Every frame's picture appended to <prefix>.rgb and the AY's sound to
// <prefix>.wav (48 kHz mono), for a video.
class Recorder {
public:
    Recorder(ein::Machine& m, const std::string& prefix)
        : m_(m), prefix_(prefix), video_(prefix + ".rgb", std::ios::binary),
          frame_(ein::Tms9129::kWidth * ein::Tms9129::kHeight), rgb_(frame_.size() * 3), samples_(4096) {
        m_.psg.set_audio_enabled(true);
        m_.psg.clear_samples();
    }
    void frame() {
        m_.vdp.render(frame_.data());
        for (std::size_t p = 0; p < frame_.size(); ++p) {
            rgb_[p * 3] = char((frame_[p] >> 16) & 0xff);
            rgb_[p * 3 + 1] = char((frame_[p] >> 8) & 0xff);
            rgb_[p * 3 + 2] = char(frame_[p] & 0xff);
        }
        video_.write(rgb_.data(), std::streamsize(rgb_.size()));
        ++frames_;
        for (int got; (got = m_.psg.read_samples(samples_.data(), int(samples_.size()))) > 0;)
            for (int s = 0; s < got; ++s)
                audio_.push_back(std::int16_t(std::clamp(samples_[s], -1.0f, 1.0f) * 32000.0f));
    }
    void finish() {
        std::ofstream wav(prefix_ + ".wav", std::ios::binary);
        const auto u32 = [&](std::uint32_t v) { wav.write(reinterpret_cast<const char*>(&v), 4); };
        const auto u16 = [&](std::uint16_t v) { wav.write(reinterpret_cast<const char*>(&v), 2); };
        const std::uint32_t bytes = std::uint32_t(audio_.size() * 2);
        wav.write("RIFF", 4); u32(36 + bytes); wav.write("WAVEfmt ", 8); u32(16); u16(1); u16(1);
        u32(ein::Ay38910::kSampleRate); u32(ein::Ay38910::kSampleRate * 2); u16(2); u16(16);
        wav.write("data", 4); u32(bytes);
        wav.write(reinterpret_cast<const char*>(audio_.data()), std::streamsize(bytes));
        std::printf("recorded=%d\nrecord_samples=%zu\n", frames_, audio_.size());
    }

private:
    ein::Machine& m_;
    std::string prefix_;
    std::ofstream video_;
    std::vector<std::uint32_t> frame_;
    std::vector<char> rgb_;
    std::vector<float> samples_;
    std::vector<std::int16_t> audio_;
    int frames_ = 0;
};

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4) {
        std::fprintf(stderr, "usage: speedrun_check <mos.rom> <disk.dsk> <speedrun.sym> command...\n");
        return 2;
    }
    const ein::RomImage rom = ein::load_rom(argv[1]);
    if (rom.data.empty()) { std::fprintf(stderr, "cannot load ROM %s\n", argv[1]); return 2; }
    const auto symbols = load_symbols(argv[3]);
    if (symbols.empty()) { std::fprintf(stderr, "no symbols in %s\n", argv[3]); return 2; }

    ein::Machine m;
    m.set_rom(rom);
    m.reset();
    m.fdc.disk(0).load(argv[2]);
    if (!m.fdc.disk(0).loaded()) { std::fprintf(stderr, "cannot load disk %s\n", argv[2]); return 2; }

    auto symbol = [&](const std::string& text) -> std::uint16_t {
        const std::size_t plus = text.find('+');
        const std::string name = text.substr(0, plus);
        const int offset = plus == std::string::npos ? 0 : std::stoi(text.substr(plus + 1));
        const auto it = symbols.find(name);
        if (it == symbols.end()) { std::fprintf(stderr, "unknown symbol %s\n", name.c_str()); std::exit(2); }
        return static_cast<std::uint16_t>(it->second + offset);
    };

    std::function<void()> recorder_stop;
    for (int i = 4; i < argc; ++i) {
        const std::string command = argv[i];
        auto next = [&]() -> std::string {
            if (++i >= argc) { std::fprintf(stderr, "%s needs an argument\n", command.c_str()); std::exit(2); }
            return argv[i];
        };
        if (command == "boot") {
            const std::string name = next();
            run_seconds(m, 7.0);
            type_text(m, name + "\n");
            const std::uint16_t pc = symbol("MainLoop");
            const std::uint64_t limit = m.tstates + std::uint64_t(120.0 * ein::Machine::kCpuClockHz);
            while (!at_program_pc(m, pc) && m.tstates < limit) step(m);
            g_fast_at_boot = m.vdp.fast_accesses();
            std::printf("main_loop=%d\nboot_seconds=%.1f\n", at_program_pc(m, pc) ? 1 : 0,
                        double(m.tstates) / ein::Machine::kCpuClockHz);
        } else if (command == "seconds") {
            run_seconds(m, std::stod(next()));
        } else if (command == "frames") {
            run_frames(m, std::stoi(next()));
        } else if (command == "hold") {
            std::stringstream keys(next());
            std::string key;
            while (std::getline(keys, key, ',')) {
                const auto it = kGameKeys.find(key);
                if (it == kGameKeys.end()) { std::fprintf(stderr, "unknown key %s\n", key.c_str()); return 2; }
                m.keyboard.set_key(it->second.row, it->second.col, true);
            }
        } else if (command == "release") {
            m.keyboard.release_all();
        } else if (command == "joy") {
            // joy X Y FIRE: joystick 1 on the ADC0844 (channel 0 X, 0 left and
            // 255 right; channel 1 Y, 0 down and 255 up; 128 at rest), its fire
            // on port 20 bit 0 (low when held), as Albert's sticks
            const int x = std::stoi(next());
            const int y = std::stoi(next());
            const int fire = std::stoi(next());
            m.adc.set_axis(0, static_cast<std::uint8_t>(x));
            m.adc.set_axis(1, static_cast<std::uint8_t>(y));
            m.keyboard.set_port20_low(fire ? 0x01 : 0x00);
        } else if (command == "peek8") {
            const std::string name = next();
            std::printf("%s=%u\n", name.c_str(), m.peek(symbol(name)));
        } else if (command == "peek16") {
            const std::string name = next();
            const std::uint16_t a = symbol(name);
            std::printf("%s=%u\n", name.c_str(), unsigned(m.peek(a) | (m.peek(std::uint16_t(a + 1)) << 8)));
        } else if (command == "mem") {
            const std::string address_text = next();
            const auto address = static_cast<std::uint16_t>(std::stoul(address_text, nullptr, 16));
            const int length = std::stoi(next());
            std::vector<std::uint8_t> bytes;
            for (int k = 0; k < length; ++k) bytes.push_back(m.peek(std::uint16_t(address + k)));
            std::printf("mem_%s=%s\n", address_text.c_str(), hex_bytes(bytes).c_str());
        } else if (command == "vram") {
            const std::string address_text = next();
            const auto address = static_cast<std::uint16_t>(std::stoul(address_text, nullptr, 16));
            const int length = std::stoi(next());
            std::vector<std::uint8_t> bytes;
            for (int k = 0; k < length; ++k) bytes.push_back(m.vdp.vram(std::uint16_t(address + k)));
            std::printf("vram_%s=%s\n", address_text.c_str(), hex_bytes(bytes).c_str());
        } else if (command == "shot") {
            save_ppm(m, next());
        } else if (command == "rec_start") {
            // rec_start PREFIX: from here every frame (whatever the commands)
            // to PREFIX.rgb and the sound to PREFIX.wav, until rec_stop
            static std::unique_ptr<Recorder> live;
            live = std::make_unique<Recorder>(m, next());
            g_last_frame = m.vdp.frames();
            g_on_frame = [&]() { live->frame(); };
            recorder_stop = [&]() { g_on_frame = nullptr; live->finish(); live.reset(); };
        } else if (command == "rec_stop") {
            if (recorder_stop) recorder_stop();
            recorder_stop = nullptr;
        } else if (command == "type") {
            std::string text = next();
            for (std::size_t k; (k = text.find("\\n")) != std::string::npos;) text.replace(k, 2, "\n");
            type_text(m, text);
        } else if (command == "wait16") {
            // wait16 SYM VALUE: run until the 16-bit SYM reaches VALUE (at most
            // 300 s); prints the TV frames that took (for benchmarks)
            const std::uint16_t a = symbol(next());
            const unsigned target = static_cast<unsigned>(std::stoul(next()));
            const std::uint64_t f0 = m.vdp.frames();
            const std::uint64_t limit = m.tstates + std::uint64_t(300.0 * ein::Machine::kCpuClockHz);
            while (unsigned(m.peek(a) | (m.peek(std::uint16_t(a + 1)) << 8)) < target && m.tstates < limit) step(m);
            std::printf("wait16_frames=%llu\n", (unsigned long long)(m.vdp.frames() - f0));
        } else if (command == "until") {
            const std::string name = next();
            const std::uint16_t pc = symbol(name);
            const std::uint64_t limit = m.tstates + std::uint64_t(std::stod(next()) * ein::Machine::kCpuClockHz);
            while (!at_program_pc(m, pc) && m.tstates < limit) step(m);
            std::printf("until_%s=%d\n", name.c_str(), at_program_pc(m, pc) ? 1 : 0);
        } else if (command == "record") {
            const int count = std::stoi(next());
            Recorder recorder(m, next());
            for (int k = 0; k < count; ++k) {
                run_frames(m, 1);
                recorder.frame();
            }
            recorder.finish();
        } else if (command == "profile" || command == "profilel") {
            const bool locals = command == "profilel";  // (local labels too)
            std::vector<std::pair<std::uint16_t, std::string>> labels;
            for (const auto& [name, address] : symbols)
                if ((locals || name.find('.') == std::string::npos) && address >= 0x0100) labels.emplace_back(address, name);
            std::sort(labels.begin(), labels.end());
            std::map<std::string, std::uint64_t> spent, calls;
            const int count = std::stoi(next());
            const auto target = m.vdp.frames() + std::uint64_t(count);
            const auto start = m.tstates;
            while (m.vdp.frames() < target) {
                const auto pc = m.cpu.pc.w;
                const auto before = m.tstates;
                m.step();
                auto it = std::upper_bound(labels.begin(), labels.end(), std::make_pair(pc, std::string("\x7f")));
                const std::string name = (it == labels.begin()) ? std::string("(below)") : std::prev(it)->second;
                spent[name] += m.tstates - before;
                if (it != labels.begin() && std::prev(it)->first == pc) ++calls[name];
            }
            std::vector<std::pair<std::uint64_t, std::string>> order;
            for (const auto& [name, t] : spent) order.emplace_back(t, name);
            std::sort(order.rbegin(), order.rend());
            const double total = double(m.tstates - start);
            for (std::size_t k = 0; k < order.size() && k < 80; ++k)
                std::printf("profile=%-24s %9.0f T a frame %5.1f%% %8.2f calls a frame\n", order[k].second.c_str(),
                            double(order[k].first) / count, 100.0 * double(order[k].first) / total,
                            double(calls[order[k].second]) / count);
        } else if (command == "linehist") {
            // linehist SYM N: run N TV frames; the raster lines (by 8) at which
            // the PC reached SYM
            const std::uint16_t at = symbol(next());
            const int count = std::stoi(next());
            const auto target = m.vdp.frames() + std::uint64_t(count);
            std::map<int, int> hist;
            while (m.vdp.frames() < target) {
                if (m.cpu.pc.w == at) ++hist[m.vdp.line() / 8];
                m.step();
            }
            for (const auto& [l, n] : hist) std::printf("line=%d %d\n", l * 8, n);
        } else if (command == "flagtrace") {
            // flagtrace SYM N: for N TV frames, when the PC reaches SYM later
            // than raster line 216, where the CPU was (and its IFF1) at each
            // 1000 T from the frame flag (line 192) on
            const std::uint16_t at = symbol(next());
            const int count = std::stoi(next());
            std::vector<std::pair<std::uint16_t, std::string>> labels;
            for (const auto& [name, address] : symbols)
                if (address >= 0x0100) labels.emplace_back(address, name);
            std::sort(labels.begin(), labels.end());
            auto name_of = [&](std::uint16_t pc) {
                auto it = std::upper_bound(labels.begin(), labels.end(), std::make_pair(pc, std::string("\x7f")));
                return it == labels.begin() ? std::string("(below)") : std::prev(it)->second;
            };
            const auto target = m.vdp.frames() + std::uint64_t(count);
            std::vector<std::string> trail;     // (the last 100: every 1000 T)
            std::uint64_t mark = m.tstates;
            const std::uint16_t isr = symbol("EinIsr"), seen = symbol("EinIsr.seen");
            while (m.vdp.frames() < target) {
                const int line = m.vdp.line();
                if (m.cpu.pc.w == isr || m.cpu.pc.w == seen) {
                    trail.push_back(std::to_string(line) + (m.cpu.pc.w == isr ? " ISR" : " SEEN"));
                    if (trail.size() > 600) trail.erase(trail.begin());
                }
                if (m.tstates >= mark) {
                    trail.push_back(std::to_string(line) + " " + name_of(m.cpu.pc.w) + (m.cpu.iff1 ? "" : "(di)"));
                    if (trail.size() > 600) trail.erase(trail.begin());
                    mark += 1000;
                }
                if (m.cpu.pc.w == at && line > 216) {
                    std::printf("late at line %d:\n", line);
                    for (const auto& t : trail) std::printf("  %s\n", t.c_str());
                }
                m.step();
            }
        } else if (command == "fastpc") {
            // fastpc N: run N TV frames; the routines (by symbol) whose VRAM
            // writes came too fast, with counts
            std::vector<std::pair<std::uint16_t, std::string>> labels;
            for (const auto& [name, address] : symbols)
                if (address >= 0x0100) labels.emplace_back(address, name);
            std::sort(labels.begin(), labels.end());
            std::map<std::string, int> where;
            std::map<int, int> lines;   // (by 16 lines of the raster)
            const int count = std::stoi(next());
            const auto target = m.vdp.frames() + std::uint64_t(count);
            while (m.vdp.frames() < target) {
                const auto pc = m.cpu.pc.w;
                const auto before = m.vdp.fast_accesses();
                m.step();
                if (m.vdp.fast_accesses() != before) {
                    ++lines[m.vdp.line() / 16];
                    auto it = std::upper_bound(labels.begin(), labels.end(), std::make_pair(pc, std::string("\x7f")));
                    ++where[it == labels.begin() ? std::string("(below)") : std::prev(it)->second];
                }
            }
            for (const auto& [l, n] : lines) std::printf("fastline=%d %d\n", l * 16, n);
            for (const auto& [name, n] : where) std::printf("fastpc=%s %d\n", name.c_str(), n);
        } else if (command == "stats") {
            std::printf("vdp_frames=%llu\nfast_vram_accesses=%llu\ninterrupts=%llu\npc=%04X\nrom_enabled=%d\nvdp_mode=%d\n",
                        (unsigned long long)m.vdp.frames(),
                        (unsigned long long)(m.vdp.fast_accesses() - g_fast_at_boot),
                        (unsigned long long)m.interrupts_taken, m.cpu.pc.w, m.rom_enabled ? 1 : 0,
                        int(m.vdp.mode()));
        } else {
            std::fprintf(stderr, "unknown command %s\n", command.c_str());
            return 2;
        }
    }
    return 0;
}
