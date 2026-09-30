'use strict';
/**
 * Mock financing provider used for local demos and contract tests.
 * Implements the same contract the Apex FinancingApiClient expects.
 *
 *   POST /v1/applications   -> 201 { applicationId, status, message }
 *   GET  /v1/applications/:id
 *   GET  /health
 *
 * Behaviour (deterministic, synthetic):
 *   - Idempotency-Key header required; repeating a key returns the original application.
 *   - Missing/invalid fields -> 400 with a validation message.
 *   - systemPrice > 100000 -> DECLINED, otherwise SUBMITTED.
 *   - Header `X-Mock-Fail: 503` forces a transient error (to demo client retries).
 *
 * No authentication is implemented; do not expose this server publicly.
 */
const http = require('node:http');

function createServer({ logger = console } = {}) {
    const applications = new Map(); // idempotencyKey -> application
    let sequence = 1000;

    const send = (res, status, body) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(body));
    };

    const validate = (body) => {
        const errors = [];
        if (!body || typeof body !== 'object') return ['body must be a JSON object'];
        if (!body.externalId) errors.push('externalId is required');
        if (typeof body.systemPrice !== 'number' || body.systemPrice <= 0) errors.push('systemPrice must be a positive number');
        if (![120, 180, 240, 300].includes(body.termMonths)) errors.push('termMonths must be 120, 180, 240 or 300');
        if (!/^\d{5}$/.test(body.postalCode || '')) errors.push('postalCode must be a 5-digit US ZIP code');
        return errors;
    };

    return http.createServer((req, res) => {
        const started = Date.now();
        res.on('finish', () => logger.log(JSON.stringify({ method: req.method, url: req.url, status: res.statusCode, ms: Date.now() - started })));

        if (req.method === 'GET' && req.url === '/health') return send(res, 200, { status: 'ok' });

        const forced = Number(req.headers['x-mock-fail']);
        if ([429, 500, 502, 503, 504].includes(forced)) return send(res, forced, { error: 'forced failure' });

        if (req.method === 'GET' && req.url.startsWith('/v1/applications/')) {
            const id = decodeURIComponent(req.url.split('/').pop());
            const found = [...applications.values()].find((a) => a.applicationId === id);
            return found ? send(res, 200, found) : send(res, 404, { error: 'not found' });
        }

        if (req.method === 'POST' && req.url === '/v1/applications') {
            const key = req.headers['idempotency-key'];
            if (!key) return send(res, 400, { error: 'Idempotency-Key header is required' });

            let raw = '';
            req.on('data', (chunk) => {
                raw += chunk;
                if (raw.length > 1e5) req.destroy(); // guard against oversized bodies
            });
            req.on('end', () => {
                if (applications.has(key)) return send(res, 200, applications.get(key));
                let body;
                try {
                    body = JSON.parse(raw);
                } catch {
                    return send(res, 400, { error: 'malformed JSON' });
                }
                const errors = validate(body);
                if (errors.length) return send(res, 400, { error: errors.join('; ') });

                const application = {
                    applicationId: `APP-${++sequence}`,
                    status: body.systemPrice > 100000 ? 'DECLINED' : 'SUBMITTED',
                    message: body.systemPrice > 100000 ? 'System price exceeds program limit' : 'Application received'
                };
                applications.set(key, application);
                return send(res, 201, application);
            });
            return undefined;
        }

        return send(res, 404, { error: 'route not found' });
    });
}

if (require.main === module) {
    const port = Number(process.env.PORT || 4010);
    createServer().listen(port, () => console.log(`Mock financing API listening on http://localhost:${port}`));
}

module.exports = { createServer };
