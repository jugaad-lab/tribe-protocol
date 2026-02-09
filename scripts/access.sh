#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/db.sh"
check_db

COMMAND="${1:-}"
shift 2>/dev/null || true

case "$COMMAND" in
    grant)
        DISCORD_ID="${1:-}"
        shift 2>/dev/null || true
        SERVER=""
        CHANNEL=""
        CHANNEL_NAME=""
        READ_ONLY=0
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --server) SERVER="$2"; shift 2 ;;
                --channel) CHANNEL="$2"; shift 2 ;;
                --channel-name) CHANNEL_NAME="$2"; shift 2 ;;
                --read-only) READ_ONLY=1; shift ;;
                *) shift ;;
            esac
        done

        if [ -z "$DISCORD_ID" ] || [ -z "$SERVER" ]; then
            echo "Usage: tribe grant <discord_id> --server <slug> [--channel <id>] [--read-only]"
            exit 1
        fi

        ENTITY_ID=$(resolve_entity_id "$DISCORD_ID")
        if [ -z "$ENTITY_ID" ]; then
            echo "❌ Entity not found for discord:$DISCORD_ID"
            exit 1
        fi

        NAME=$(db_query "SELECT name FROM entities WHERE id=$ENTITY_ID;")
        CAN_WRITE=$((1 - READ_ONLY))
        CHAN_CLAUSE="NULL"
        [ -n "$CHANNEL" ] && CHAN_CLAUSE="'$CHANNEL'"
        CHAN_NAME_CLAUSE="NULL"
        [ -n "$CHANNEL_NAME" ] && CHAN_NAME_CLAUSE="'$CHANNEL_NAME'"

        db_query "INSERT OR REPLACE INTO channel_access (entity_id, server_slug, channel_id, channel_name, can_read, can_write)
            VALUES ($ENTITY_ID, '$SERVER', $CHAN_CLAUSE, $CHAN_NAME_CLAUSE, 1, $CAN_WRITE);"

        db_query "INSERT INTO audit_log (entity_id, action, new_value, changed_by)
            VALUES ($ENTITY_ID, 'grant-access', 'server=$SERVER channel=${CHANNEL:-all} write=$CAN_WRITE', 'tribe-cli');"

        SCOPE="${CHANNEL:-all channels}"
        PERM="read/write"
        [ "$READ_ONLY" = "1" ] && PERM="read-only"
        echo "✅ Granted $NAME $PERM access to $SERVER ($SCOPE)"
        ;;

    revoke)
        DISCORD_ID="${1:-}"
        shift 2>/dev/null || true
        SERVER=""
        CHANNEL=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --server) SERVER="$2"; shift 2 ;;
                --channel) CHANNEL="$2"; shift 2 ;;
                *) shift ;;
            esac
        done

        if [ -z "$DISCORD_ID" ] || [ -z "$SERVER" ]; then
            echo "Usage: tribe revoke <discord_id> --server <slug> [--channel <id>]"
            exit 1
        fi

        ENTITY_ID=$(resolve_entity_id "$DISCORD_ID")
        if [ -z "$ENTITY_ID" ]; then
            echo "❌ Entity not found for discord:$DISCORD_ID"
            exit 1
        fi

        NAME=$(db_query "SELECT name FROM entities WHERE id=$ENTITY_ID;")

        if [ -n "$CHANNEL" ]; then
            db_query "DELETE FROM channel_access WHERE entity_id=$ENTITY_ID AND server_slug='$SERVER' AND channel_id='$CHANNEL';"
        else
            db_query "DELETE FROM channel_access WHERE entity_id=$ENTITY_ID AND server_slug='$SERVER';"
        fi

        db_query "INSERT INTO audit_log (entity_id, action, old_value, changed_by)
            VALUES ($ENTITY_ID, 'revoke-access', 'server=$SERVER channel=${CHANNEL:-all}', 'tribe-cli');"

        echo "✅ Revoked $NAME access from $SERVER (${CHANNEL:-all channels})"
        ;;

    *)
        echo "Usage: tribe grant <discord_id> --server <slug> [--channel <id>] [--read-only]"
        echo "       tribe revoke <discord_id> --server <slug> [--channel <id>]"
        exit 1
        ;;
esac
