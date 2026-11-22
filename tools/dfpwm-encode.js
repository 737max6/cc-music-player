/**
 * DFPWM encoder: 8-bit PCM (48 kHz mono) -> DFPWM, for CC: Tweaked speakers.
 *
 * The algorithm is a JavaScript port of CC: Tweaked's `cc.audio.dfpwm` module
 * (https://github.com/cc-tweaked/CC-Tweaked), which is licensed under MPL-2.0.
 * This file is therefore distributed under MPL-2.0 as well.
 *
 * Usage as a module:
 *   const { createEncoder } = require('./dfpwm-encode');
 *   const enc = createEncoder();
 *   out.write(enc.push(pcmBuffer));   // any chunk size
 *   out.write(enc.flush());           // at the end
 *
 * Usage as a CLI (whole stream at once):
 *   ffmpeg -i song.mp3 -f s8 -ac 1 -ar 48000 - | node dfpwm-encode.js > song.dfpwm
 */
'use strict';

const PREC = 10;
const PREC_POW = 1024;
const PREC_POW_HALF = 512;
const STRENGTH_MIN = 8;
const GROUP = 8; // 8 samples per output byte

function createEncoder() {
    let charge = 0;
    let strength = 0;
    let previousBit = false;
    let previousCharge = 0;
    let rest = Buffer.alloc(0);

    function predict(bit) {
        const target = bit ? 127 : -128;
        let nextCharge = charge + Math.floor((strength * (target - charge) + PREC_POW_HALF) / PREC_POW);
        if (nextCharge === charge && nextCharge !== target) nextCharge += bit ? 1 : -1;

        const z = bit === previousBit ? PREC_POW - 1 : 0;
        let nextStrength = strength;
        if (nextStrength !== z) nextStrength += bit === previousBit ? 1 : -1;
        if (nextStrength < STRENGTH_MIN) nextStrength = STRENGTH_MIN;

        charge = nextCharge;
        strength = nextStrength;
        previousBit = bit;
        return charge;
    }

    /** Encode all complete groups of 8 samples in `data`, keep the remainder. */
    function encodeGroups(data) {
        const count = data.length - (data.length % GROUP);
        if (count === 0) return Buffer.alloc(0);

        const out = Buffer.alloc(count / GROUP);
        let o = 0;
        for (let i = 0; i < count; i += GROUP) {
            let byte = 0;
            for (let j = 0; j < GROUP; j++) {
                let v = data[i + j];
                if (v > 127) v -= 256; // unsigned byte -> signed amplitude
                const bit = v > previousCharge || (v === previousCharge && v === 127);
                byte = Math.floor(byte / 2) + (bit ? 128 : 0);
                previousCharge = predict(bit);
            }
            out[o++] = byte;
        }
        rest = Buffer.from(data.subarray(count));
        return out;
    }

    return {
        /** Feed any number of PCM bytes, returns the DFPWM bytes ready so far. */
        push(chunk) {
            const data = rest.length ? Buffer.concat([rest, chunk]) : chunk;
            return encodeGroups(data);
        },
        /** Flush the trailing partial group (padded with silence). */
        flush() {
            if (rest.length === 0) return Buffer.alloc(0);
            const padded = Buffer.concat([rest, Buffer.alloc(GROUP - rest.length)]);
            rest = Buffer.alloc(0);
            return encodeGroups(padded);
        },
    };
}

module.exports = { createEncoder };

if (require.main === module) {
    const chunks = [];
    process.stdin.on('data', (c) => chunks.push(c));
    process.stdin.on('end', () => {
        const enc = createEncoder();
        process.stdout.write(enc.push(Buffer.concat(chunks)));
        process.stdout.write(enc.flush());
    });
}
