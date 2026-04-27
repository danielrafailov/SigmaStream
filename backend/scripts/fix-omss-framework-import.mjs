/**
 * Some @omss/framework builds ship dist/core/server.js with a broken bare import:
 *   from 'src/controllers/mcp.controller.js'
 * Node resolves `src` as a package name → ERR_MODULE_NOT_FOUND.
 * Rewrite to the correct relative path next to dist/core/.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverJs = path.join(__dirname, '../node_modules/@omss/framework/dist/core/server.js');

if (!fs.existsSync(serverJs)) {
    process.exit(0);
}

let source = fs.readFileSync(serverJs, 'utf8');
const broken =
    /import\s*\{\s*MCPController\s*\}\s*from\s*['"]src\/controllers\/mcp\.controller\.js['"]\s*;/;
const fixed = "import { MCPController } from '../controllers/mcp.controller.js';";

if (broken.test(source)) {
    source = source.replace(broken, fixed);
    fs.writeFileSync(serverJs, source);
    console.log('[postinstall] Patched @omss/framework dist/core/server.js (MCP import path).');
}
