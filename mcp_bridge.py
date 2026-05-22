#!/usr/bin/env python3
"""MCP stdio bridge for self-hosted mem0.

Translates MCP tool calls to mem0 OSS REST API.
Drop-in replacement for cloud mcp.mem0.ai endpoint.

Env vars:
  MEM0_BASE_URL  — self-hosted server URL (required)
  MEM0_API_KEY   — admin API key or per-user key
"""

import json
import os
import sys
import urllib.error
import urllib.request

BASE_URL = os.environ.get("MEM0_BASE_URL", "").rstrip("/")
API_KEY = os.environ.get("MEM0_API_KEY", "")

if not BASE_URL:
    print(
        "mem0 MCP bridge: MEM0_BASE_URL is required. "
        "Set it in your MCP server env config or shell profile.",
        file=sys.stderr,
    )
    sys.exit(1)

TOOLS = [
    {
        "name": "add_memory",
        "description": (
            "Save text or conversation history for a user/agent. "
            "Call this when the user shares information worth remembering, "
            "or when the user asks you to remember something."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "messages": {
                    "anyOf": [
                        {"type": "string"},
                        {"type": "array", "items": {"type": "object"}},
                    ],
                    "description": "Message content. Strings auto-convert to user messages.",
                },
                "user_id": {"type": "string", "description": "User identifier"},
                "agent_id": {"type": "string", "description": "Agent identifier"},
                "app_id": {"type": "string", "description": "Application identifier"},
                "run_id": {"type": "string", "description": "Session/run identifier"},
                "metadata": {"type": "object", "description": "Custom key-value pairs"},
                "infer": {
                    "type": "boolean",
                    "description": "If false, store raw text without LLM inference",
                    "default": True,
                },
            },
            "required": ["messages"],
        },
    },
    {
        "name": "search_memories",
        "description": "Semantic search across existing memories with filters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Natural language search query"},
                "user_id": {"type": "string", "description": "User identifier"},
                "agent_id": {"type": "string", "description": "Agent identifier"},
                "run_id": {"type": "string", "description": "Run identifier"},
                "limit": {"type": "integer", "description": "Number of results", "default": 10},
                "filters": {"type": "object", "description": "Filter conditions"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_memories",
        "description": "List memories with filters and pagination.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "agent_id": {"type": "string"},
                "run_id": {"type": "string"},
                "app_id": {"type": "string"},
            },
        },
    },
    {
        "name": "get_memory",
        "description": "Retrieve a specific memory by ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "memory_id": {"type": "string", "description": "Memory ID to retrieve"},
            },
            "required": ["memory_id"],
        },
    },
    {
        "name": "update_memory",
        "description": "Overwrite a memory's text by ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "memory_id": {"type": "string", "description": "Memory ID"},
                "text": {"type": "string", "description": "New memory content"},
            },
            "required": ["memory_id", "text"],
        },
    },
    {
        "name": "delete_memory",
        "description": "Delete a single memory by ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "memory_id": {"type": "string", "description": "Memory ID to delete"},
            },
            "required": ["memory_id"],
        },
    },
    {
        "name": "delete_all_memories",
        "description": "Bulk delete all memories in scope.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "agent_id": {"type": "string"},
                "run_id": {"type": "string"},
                "app_id": {"type": "string"},
            },
        },
    },
    {
        "name": "delete_entities",
        "description": "Delete a user/agent/app/run entity and its memories.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "entity_type": {
                    "type": "string",
                    "enum": ["user", "agent", "run"],
                    "description": "Entity type",
                },
                "entity_id": {"type": "string", "description": "Entity identifier"},
            },
            "required": ["entity_type", "entity_id"],
        },
    },
    {
        "name": "list_entities",
        "description": "List users/agents/apps/runs stored in mem0.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
]


def api_request(method, path, body=None, params=None):
    url = f"{BASE_URL}{path}"
    if params:
        qs = "&".join(f"{k}={v}" for k, v in params.items() if v is not None)
        if qs:
            url += f"?{qs}"

    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["X-API-Key"] = API_KEY

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        return {"error": f"HTTP {e.code}: {error_body}"}
    except Exception as e:
        return {"error": str(e)}


def handle_tool(name, arguments):
    if name == "add_memory":
        messages = arguments.get("messages")
        if isinstance(messages, str):
            messages = [{"role": "user", "content": messages}]
        body = {"messages": messages}
        for k in ("user_id", "agent_id", "app_id", "run_id", "metadata", "infer"):
            if k in arguments and arguments[k] is not None:
                body[k] = arguments[k]
        return api_request("POST", "/memories", body)

    elif name == "search_memories":
        body = {"query": arguments["query"]}
        if "limit" in arguments and arguments["limit"] is not None:
            body["limit"] = arguments["limit"]
        # mem0 OSS requires entity params inside filters, not top-level
        filters = arguments.get("filters") or {}
        for k in ("user_id", "agent_id", "run_id"):
            if k in arguments and arguments[k] is not None:
                filters[k] = arguments[k]
        if filters:
            body["filters"] = filters
        return api_request("POST", "/search", body)

    elif name == "get_memories":
        params = {}
        for k in ("user_id", "agent_id", "run_id", "app_id"):
            if k in arguments and arguments[k] is not None:
                params[k] = arguments[k]
        return api_request("GET", "/memories", params=params)

    elif name == "get_memory":
        return api_request("GET", f"/memories/{arguments['memory_id']}")

    elif name == "update_memory":
        return api_request(
            "PUT", f"/memories/{arguments['memory_id']}", {"text": arguments["text"]}
        )

    elif name == "delete_memory":
        return api_request("DELETE", f"/memories/{arguments['memory_id']}")

    elif name == "delete_all_memories":
        params = {}
        for k in ("user_id", "agent_id", "run_id", "app_id"):
            if k in arguments and arguments[k] is not None:
                params[k] = arguments[k]
        return api_request("DELETE", "/memories", params=params)

    elif name == "delete_entities":
        etype = arguments["entity_type"]
        eid = arguments["entity_id"]
        return api_request("DELETE", f"/entities/{etype}/{eid}")

    elif name == "list_entities":
        return api_request("GET", "/entities")

    else:
        return {"error": f"Unknown tool: {name}"}


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = msg.get("method")
        msg_id = msg.get("id")

        if msg_id is None:
            continue

        if method == "initialize":
            send(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {}},
                        "serverInfo": {
                            "name": "mem0-self-hosted",
                            "version": "1.0.0",
                        },
                    },
                }
            )

        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": msg_id, "result": {"tools": TOOLS}})

        elif method == "tools/call":
            params = msg.get("params", {})
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            result = handle_tool(tool_name, arguments)
            is_error = "error" in result and len(result) == 1
            send(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "content": [
                            {"type": "text", "text": json.dumps(result, indent=2)}
                        ],
                        "isError": is_error,
                    },
                }
            )

        elif method == "ping":
            send({"jsonrpc": "2.0", "id": msg_id, "result": {}})

        else:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {method}",
                    },
                }
            )


if __name__ == "__main__":
    main()
