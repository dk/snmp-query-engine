#include "sqe.h"

/*
 * info request:
 * [ 0, $cid ]
 *
 */

static int
pack_stats(struct program_stats *PS, msgpack_packer *pk)
{
	int n = 0;

	#define STAT(what) if (PS->what >= 0) { n++; if (pk) msgpack_pack_named_int(pk, #what, PS->what); }

	STAT(active_client_connections);
	STAT(total_client_connections);

	STAT(client_requests);
	STAT(invalid_requests);

	STAT(snmp_sends);
	STAT(snmp_retries);


	#undef STAT
	return n;
}

int
handle_info_request(struct socket_info *si, unsigned cid, msgpack_object *o)
{
	msgpack_sbuffer* buffer;
	msgpack_packer* pk;
	char *key;
	int l;

	if (o->via.array.size != 2)
		return error_reply(si, RT_INFO|RT_ERROR, cid, "bad request length");

	buffer = msgpack_sbuffer_new();
	pk = msgpack_packer_new(buffer, msgpack_sbuffer_write);
	msgpack_pack_array(pk, 3);
	msgpack_pack_int(pk, RT_INFO|RT_REPLY);
	msgpack_pack_int(pk, cid);
	msgpack_pack_map(pk, 2);

	key = "global";
	l = strlen(key);
	msgpack_pack_raw(pk, l);
	msgpack_pack_raw_body(pk, key, l);
	msgpack_pack_map(pk, pack_stats(&PS, NULL));
	pack_stats(&PS, pk);

	key = "connection";
	l = strlen(key);
	msgpack_pack_raw(pk, l);
	msgpack_pack_raw_body(pk, key, l);
	msgpack_pack_map(pk, pack_stats(&si->PS, NULL));
	pack_stats(&si->PS, pk);

	tcp_send(si, buffer->data, buffer->size);
	msgpack_sbuffer_free(buffer);
	msgpack_packer_free(pk);
	return 0;
}
