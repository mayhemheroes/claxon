// Claxon -- A FLAC decoding library in Rust
// Copyright 2015 van Asseldonk
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

extern crate claxon;
extern crate hound;

fn main() {
    use std::env;
    use std::fs;
    use std::io;
    use std::path;
    use claxon::FlacReader;
    use hound::{WavSpec, WavWriter};

    let arg = env::args().nth(1).expect("no file given");
    let fname = path::Path::new(&arg);
    let input = fs::File::open(fname).expect("failed to open file");
    let mut buf_reader = io::BufReader::new(input);
    let mut reader = FlacReader::new(&mut buf_reader).expect("failed to open FLAC stream");
    let samples = reader.streaminfo().samples.expect("no sample count present in streaminfo");

    let spec = WavSpec {
        // TODO: u8 for channels, is that weird? Would u32 be better?
        channels: reader.streaminfo().channels as u16,
        sample_rate: reader.streaminfo().sample_rate,
        // TODO: again, would u32 be better, even if the range is smaller?
        bits_per_sample: reader.streaminfo().bits_per_sample as u16
    };
    let fname_wav = fname.with_extension("wav");
    let mut output = WavWriter::create(fname_wav, spec).expect("failed to create wav file");

    let mut blocks = reader.blocks::<i32>();
    let mut sample = 0u64;
    let mut i = 0u64;
    let mut buffer = Vec::new();

    while sample < samples {
        let block = blocks.read_next(buffer).ok().expect("failed to read block");
        {
            let left = block.channel(0);
            let right = block.channel(1);
            for (&l, &r) in left.iter().zip(right.iter()) {
                output.write_sample(l).ok().expect("failed to write sample");
                output.write_sample(r).ok().expect("failed to write sample");
            }
            sample = sample + block.len() as u64;
            i = i + 1;
        }
        buffer = block.into_buffer();
    }
}
