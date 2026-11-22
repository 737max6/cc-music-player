#!/usr/bin/env node
/**
 * Convert audio files (mp3 / flac / aac / wav / ogg / m4a / opus / wma)
 * into .dfpwm files that a CC: Tweaked computer can play.
 *
 *   node convert.js <music-folder> [--force]
 *
 * Output is written next to the source file, same name with .dfpwm.
 * Requires ffmpeg (in PATH, next to this script, or set FFMPEG=/path/to/ffmpeg).
 *
 * Implementation note: ffmpeg writes straight into temporary files through
 * file descriptors instead of pipes. That keeps it working on Windows with
 * non-ASCII paths and avoids pipe-related failures in restricted sandboxes.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const { createEncoder } = require('./dfpwm-encode');

const AUDIO_EXTS = ['.mp3', '.flac', '.aac', '.m4a', '.wav', '.ogg', '.opus', '.wma'];
const SAMPLE_RATE = 48000;

function findFfmpeg() {
    const candidates = [
        process.env.FFMPEG,
        path.join(__dirname, 'ffmpeg.exe'),
        path.join(__dirname, 'ffmpeg'),
        path.join(__dirname, 'ffmpeg', 'bin', 'ffmpeg.exe'),
        path.join(__dirname, 'ffmpeg', 'bin', 'ffmpeg'),
        'ffmpeg',
    ].filter(Boolean);

    for (const bin of candidates) {
        const r = spawnSync(bin, ['-version'], { stdio: 'ignore' });
        if (r.status === 0) return bin;
    }
    return null;
}

function encodeFile(pcmPath, outPath) {
    const inFd = fs.openSync(pcmPath, 'r');
    const outFd = fs.openSync(outPath, 'w');
    const buf = Buffer.alloc(64 * 1024);
    const enc = createEncoder();
    let total = 0;
    try {
        for (;;) {
            const n = fs.readSync(inFd, buf, 0, buf.length, null);
            if (n <= 0) break;
            const data = enc.push(buf.subarray(0, n));
            if (data.length) { fs.writeSync(outFd, data); total += data.length; }
        }
        const tail = enc.flush();
        if (tail.length) { fs.writeSync(outFd, tail); total += tail.length; }
    } finally {
        fs.closeSync(inFd);
        fs.closeSync(outFd);
    }
    return total;
}

function convertOne(ffmpeg, src, out, force) {
    return new Promise((resolve) => {
        if (!force && fs.existsSync(out) && fs.statSync(out).mtimeMs >= fs.statSync(src).mtimeMs) {
            return resolve({ src, out, skipped: true });
        }

        const tag = process.pid + '-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7);
        const pcmPath = path.join(os.tmpdir(), 'ccpcm-' + tag + '.s8');
        const logPath = path.join(os.tmpdir(), 'ccpcm-' + tag + '.log');

        const pcmFd = fs.openSync(pcmPath, 'w');
        const logFd = fs.openSync(logPath, 'w');

        const args = [
            '-y', '-hide_banner', '-loglevel', 'error',
            '-i', src,
            '-vn', '-sn', '-dn', '-map', '0:a:0',
            '-f', 's8', '-acodec', 'pcm_s8',
            '-ac', '1', '-ar', String(SAMPLE_RATE),
            pcmPath,
        ];

        const cleanup = () => {
            for (const p of [pcmPath, logPath]) {
                try { fs.unlinkSync(p); } catch (_) { /* ignore */ }
            }
        };

        let ff;
        try {
            ff = spawn(ffmpeg, args, { stdio: ['ignore', pcmFd, logFd] });
        } catch (err) {
            fs.closeSync(pcmFd);
            fs.closeSync(logFd);
            cleanup();
            return resolve({ src, out, error: err.message });
        }

        ff.on('error', (err) => {
            try { fs.closeSync(pcmFd); } catch (_) { /* ignore */ }
            try { fs.closeSync(logFd); } catch (_) { /* ignore */ }
            cleanup();
            resolve({ src, out, error: err.message });
        });

        ff.on('close', (code) => {
            try { fs.closeSync(pcmFd); } catch (_) { /* ignore */ }
            try { fs.closeSync(logFd); } catch (_) { /* ignore */ }

            if (code !== 0) {
                let msg = 'ffmpeg exit ' + code;
                try {
                    const log = fs.readFileSync(logPath, 'utf8').trim();
                    if (log) msg = log.split(/\r?\n/).pop();
                } catch (_) { /* ignore */ }
                cleanup();
                return resolve({ src, out, error: msg });
            }

            let size = 0;
            try {
                size = encodeFile(pcmPath, out);
            } catch (err) {
                cleanup();
                return resolve({ src, out, error: err.message });
            }
            cleanup();

            if (size < 1000) {
                try { fs.unlinkSync(out); } catch (_) { /* ignore */ }
                return resolve({ src, out, error: 'output too small (' + size + ' bytes)' });
            }
            resolve({ src, out, size });
        });
    });
}

async function main() {
    const args = process.argv.slice(2);
    const force = args.includes('--force');
    const dir = args.find((a) => !a.startsWith('--'));

    if (!dir) {
        console.log('usage: node convert.js <music-folder> [--force]');
        process.exit(1);
    }
    if (!fs.existsSync(dir)) {
        console.error('folder not found: ' + dir);
        process.exit(1);
    }

    const ffmpeg = findFfmpeg();
    if (!ffmpeg) {
        console.error('ffmpeg not found.');
        console.error('Install it, or put ffmpeg(.exe) next to this script,');
        console.error('or set FFMPEG to its full path.');
        process.exit(1);
    }
    console.log('ffmpeg: ' + ffmpeg);

    const files = fs.readdirSync(dir)
        .filter((f) => AUDIO_EXTS.includes(path.extname(f).toLowerCase()))
        .sort();

    if (files.length === 0) {
        console.log('no audio files in ' + dir);
        return;
    }

    let ok = 0, skipped = 0, failed = 0;
    for (const name of files) {
        const src = path.join(dir, name);
        const out = path.join(dir, name.slice(0, -path.extname(name).length) + '.dfpwm');
        process.stdout.write('[*] ' + name + ' ... ');
        const r = await convertOne(ffmpeg, src, out, force);
        if (r.error) {
            failed++;
            console.log('FAILED (' + r.error + ')');
        } else if (r.skipped) {
            skipped++;
            console.log('up to date');
        } else {
            ok++;
            console.log('OK (' + r.size + ' bytes)');
        }
    }

    console.log('');
    console.log(`done: ${ok} converted, ${skipped} up to date, ${failed} failed`);
    console.log('put the .dfpwm files into your computer\'s /music folder');
    if (failed) process.exitCode = 1;
}

main();
