package service_lab.security

test_valid_pod {
	results := violation with input as data.valid
	count(results) == 0
}

test_root_rejected {
	modified := object.union(data.valid.review.object.spec.containers[0], {"securityContext": {"runAsUser": 0}})
	spec := object.union(data.valid.review.object.spec, {"containers": [modified]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) > 0
}

test_writable_fs_rejected {
	c := data.valid.review.object.spec.containers[0]
	sc := object.union(c.securityContext, {"readOnlyRootFilesystem": false})
	changed := object.union(c, {"securityContext": sc})
	spec := object.union(data.valid.review.object.spec, {"containers": [changed]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) == 1
}

test_hostpath_rejected {
	spec := object.union(data.valid.review.object.spec, {"volumes": [{"name": "host", "hostPath": {"path": "/"}}]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) == 1
}

test_init_container_checked {
	c := object.union(data.valid.review.object.spec.containers[0], {"name": "bad-init", "securityContext": {"runAsUser": 0}})
	spec := object.union(data.valid.review.object.spec, {"initContainers": [c]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) > 0
}

test_missing_resources_rejected {
	c := object.remove(data.valid.review.object.spec.containers[0], ["resources"])
	spec := object.union(data.valid.review.object.spec, {"containers": [c]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) == 6
}

test_sidecar_nonroot_allowed {
	c := data.valid.review.object.spec.containers[0]
	sc := object.union(c.securityContext, {"runAsUser": 1337})
	proxy := object.union(c, {"name": "istio-proxy", "securityContext": sc})
	spec := object.union(data.valid.review.object.spec, {"containers": [c, proxy]})
	pod := object.union(data.valid.review.object, {"spec": spec})
	results := violation with input as {"review": {"object": pod}}
	count(results) == 0
}
