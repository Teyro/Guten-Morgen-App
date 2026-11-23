// Verschlüsselt die Vorgaben der Schule: node scripts/vorgaben.mjs <klartext.json> <Schul-Code> [ausgabe]
// Klartext NIE einchecken – nur schule/vorgaben.enc. Format siehe MorgenKern/SchulVorgaben.swift (AES-256-GCM, PBKDF2-SHA256).
import { readFileSync, writeFileSync } from "node:fs";
import { pbkdf2Sync, randomBytes, createCipheriv } from "node:crypto";
const [, , ein, code, aus = new URL("../schule/vorgaben.enc", import.meta.url).pathname] = process.argv;
if (!ein || !code) { console.error("node scripts/vorgaben.mjs <klartext.json> <Schul-Code> [ausgabe]"); process.exit(1); }
const klar = Buffer.from(JSON.stringify(JSON.parse(readFileSync(ein, "utf8"))));
const runden = 300000, salz = randomBytes(16), nonce = randomBytes(12);
const k = pbkdf2Sync(code.trim(), salz, runden, 32, "sha256");
const c = createCipheriv("aes-256-gcm", k, nonce);
const text = Buffer.concat([c.update(klar), c.final()]);
writeFileSync(aus, JSON.stringify({ v: 1, runden, salz: salz.toString("base64"), daten: Buffer.concat([nonce, text, c.getAuthTag()]).toString("base64") }) + "\n");
console.log("geschrieben:", aus);
