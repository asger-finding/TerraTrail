import { exportJWK, generateKeyPair, importJWK } from 'jose';
import { config } from '../config.js';
import path from 'path';
import { mkdir } from 'fs/promises';

let privateKey: CryptoKey;
let publicKey: CryptoKey;

const PRIVATE_KEY_PATH = path.join(config.jwtKeysDir, 'private.jwk.json');
const PUBLIC_KEY_PATH = path.join(config.jwtKeysDir, 'public.jwk.json');

export async function getKeys() {
    if (privateKey && publicKey) {
        return { privateKey, publicKey };
    }

    const privateFile = Bun.file(PRIVATE_KEY_PATH);
    const publicFile = Bun.file(PUBLIC_KEY_PATH);

    if (await privateFile.exists() && await publicFile.exists()) {
        const privJwk = await privateFile.json();
        const pubJwk = await publicFile.json();
        privateKey = await importJWK(privJwk, 'ES256') as CryptoKey;
        publicKey = await importJWK(pubJwk, 'ES256') as CryptoKey;
        console.log('JWT-nøgler indlæst fra disk');
    } else {
        await mkdir(config.jwtKeysDir, { recursive: true });
        const keyPair = await generateKeyPair('ES256', { extractable: true });
        privateKey = keyPair.privateKey;
        publicKey = keyPair.publicKey;

        await Bun.write(PRIVATE_KEY_PATH, JSON.stringify(await exportJWK(privateKey)));
        await Bun.write(PUBLIC_KEY_PATH, JSON.stringify(await exportJWK(publicKey)));
        console.log('Nye JWT-nøgler genereret og gemt');
    }

    return { privateKey, publicKey };
}
