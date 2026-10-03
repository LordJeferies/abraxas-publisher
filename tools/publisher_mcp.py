#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def ctl_command():
    installed = shutil.which("publisherctl")

    if installed:
        return [installed]

    release = (
        ROOT
        / "src-tauri"
        / "target"
        / "release"
        / "publisherctl"
    )

    if release.exists():
        return [str(release)]

    debug = (
        ROOT
        / "src-tauri"
        / "target"
        / "debug"
        / "publisherctl"
    )

    if debug.exists():
        return [str(debug)]

    return [
        "cargo",
        "run",
        "--quiet",
        "--manifest-path",
        str(
            ROOT
            / "src-tauri"
            / "Cargo.toml"
        ),
        "--bin",
        "publisherctl",
        "--",
    ]


def run_ctl(args):
    proc = subprocess.run(
        ctl_command() + args,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            proc.stderr.strip()
            or proc.stdout.strip()
            or f"publisherctl exit {proc.returncode}"
        )

    return proc.stdout.strip()


TOOLS = [
    {
        "name": "publisher_list_brands",
        "description": "Lista marcas de ABRAXAS Publisher.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_create_brand",
        "description": "Crea una marca.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                }
            },
            "required": ["name"],
        },
    },
    {
        "name": "publisher_list_content",
        "description": "Lista contenido del workspace.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_get_content",
        "description": "Obtiene una ficha de contenido por ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                }
            },
            "required": ["id"],
        },
    },
    {
        "name": "publisher_import_local_folder",
        "description": "Importa una carpeta local sin publicar nada.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                },
                "brand": {
                    "type": "string",
                },
                "duplicates": {
                    "type": "string",
                    "enum": [
                        "replace",
                        "keep",
                        "skip",
                    ],
                },
            },
            "required": [
                "path",
                "brand",
            ],
        },
    },
    {
        "name": "publisher_refresh_content",
        "description": "Refresca un contenido y detecta archivos reemplazados.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                }
            },
            "required": ["id"],
        },
    },
    {
        "name": "publisher_add_note",
        "description": "Añade una nota de corrección.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                },
                "note": {
                    "type": "string",
                },
            },
            "required": [
                "id",
                "note",
            ],
        },
    },
    {
        "name": "publisher_set_editorial_status",
        "description": "Cambia el estado editorial de un contenido.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                },
                "status": {
                    "type": "string",
                    "enum": [
                        "EN_CONFIRMACION",
                        "CON_CORRECCION",
                        "LISTO_POR_PROGRAMAR",
                        "PROGRAMADO",
                    ],
                },
            },
            "required": [
                "id",
                "status",
            ],
        },
    },
    {
        "name": "publisher_get_activity",
        "description": "Devuelve historial de actividad.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_undo",
        "description": "Deshace la última acción local reversible.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_redo",
        "description": "Rehace la última acción deshecha.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_dry_run",
        "description": "Ejecuta simulación sin publicar.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "publisher_doctor",
        "description": "Ejecuta diagnóstico local.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
]


def call_tool(name, args):
    if name == "publisher_list_brands":
        return run_ctl(
            ["brands", "list"]
        )

    if name == "publisher_create_brand":
        return run_ctl(
            [
                "brands",
                "add",
                args["name"],
            ]
        )

    if name == "publisher_list_content":
        return run_ctl(
            ["content", "list"]
        )

    if name == "publisher_get_content":
        return run_ctl(
            [
                "content",
                "show",
                args["id"],
            ]
        )

    if name == "publisher_import_local_folder":
        cmd = [
            "import",
            "local",
            args["path"],
            "--brand",
            args["brand"],
            "--duplicates",
            args.get(
                "duplicates",
                "replace",
            ),
        ]

        return run_ctl(cmd)

    if name == "publisher_refresh_content":
        return run_ctl(
            [
                "content",
                "refresh",
                args["id"],
            ]
        )

    if name == "publisher_add_note":
        return run_ctl(
            [
                "note",
                "add",
                args["id"],
                args["note"],
            ]
        )

    if name == "publisher_set_editorial_status":
        return run_ctl(
            [
                "status",
                "set",
                args["id"],
                args["status"],
            ]
        )

    if name == "publisher_get_activity":
        return run_ctl(
            ["activity"]
        )

    if name == "publisher_undo":
        return run_ctl(
            ["undo"]
        )

    if name == "publisher_redo":
        return run_ctl(
            ["redo"]
        )

    if name == "publisher_dry_run":
        return run_ctl(
            ["dry-run"]
        )

    if name == "publisher_doctor":
        return run_ctl(
            ["doctor"]
        )

    raise RuntimeError(
        f"Unknown tool: {name}"
    )


def response(req_id, result=None, error=None):
    obj = {
        "jsonrpc": "2.0",
        "id": req_id,
    }

    if error is not None:
        obj["error"] = {
            "code": -32000,
            "message": str(error),
        }
    else:
        obj["result"] = result

    sys.stdout.write(
        json.dumps(obj)
        + "\n"
    )
    sys.stdout.flush()


def self_test():
    output = run_ctl(
        ["qa"]
    )

    if "QA APPROVED" not in output:
        raise RuntimeError(
            "publisherctl qa no terminó correctamente."
        )

    print(
        "PASS publisher-mcp self-test"
    )


def main():
    if "--self-test" in sys.argv:
        self_test()
        return

    for line in sys.stdin:
        line = line.strip()

        if not line:
            continue

        try:
            message = json.loads(line)
        except Exception:
            continue

        method = message.get("method")
        req_id = message.get("id")

        if method == "notifications/initialized":
            continue

        if method == "initialize":
            response(
                req_id,
                {
                    "protocolVersion":
                        "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name":
                            "abraxas-publisher",
                        "version":
                            "0.3.0",
                    },
                },
            )
            continue

        if method == "tools/list":
            response(
                req_id,
                {
                    "tools": TOOLS
                },
            )
            continue

        if method == "tools/call":
            params = (
                message
                .get(
                    "params",
                    {},
                )
            )

            name = params.get("name")
            args = params.get(
                "arguments",
                {},
            )

            try:
                value = call_tool(
                    name,
                    args,
                )

                response(
                    req_id,
                    {
                        "content": [
                            {
                                "type":
                                    "text",
                                "text":
                                    value,
                            }
                        ],
                        "isError":
                            False,
                    },
                )
            except Exception as exc:
                response(
                    req_id,
                    {
                        "content": [
                            {
                                "type":
                                    "text",
                                "text":
                                    str(exc),
                            }
                        ],
                        "isError":
                            True,
                    },
                )

            continue

        if req_id is not None:
            response(
                req_id,
                error=
                    f"Unsupported method: {method}",
            )


if __name__ == "__main__":
    main()
