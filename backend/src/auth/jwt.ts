import { SignJWT, jwtVerify } from 'jose';
import { getKeys } from './keys.js';
import { config } from '../config.js';

export async function signToken(playerId: number, username: string): Promise<string> {
    const { privateKey } = await getKeys();
    return new SignJWT({ username })
        .setProtectedHeader({ alg: 'ES256' })
        .setSubject(String(playerId))
        .setIssuedAt()
        .setExpirationTime(config.jwtExpiration)
        .sign(privateKey);
}

export async function verifyToken(token: string): Promise<{ sub: string; username: string }> {
    const { publicKey } = await getKeys();
    const { payload } = await jwtVerify(token, publicKey, { algorithms: ['ES256'] });
    return { sub: payload.sub as string, username: payload.username as string };
}
