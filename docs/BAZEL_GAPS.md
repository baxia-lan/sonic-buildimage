# Bazel Migration Gaps vs Make Build

## Package Build Gaps

### Building from source (Make builds all, Bazel builds 6):

| Package | Make | Bazel | Gap |
|---|---|---|---|
| libnl3 | ✅ dget + dpkg-buildpackage | ✅ Docker genrule | - |
| sonic-swss-common | ✅ dpkg-buildpackage | ✅ Docker genrule | - |
| sonic-sairedis | ✅ dpkg-buildpackage | ✅ Docker genrule | - |
| sonic-dash-api | ✅ dpkg-buildpackage | ✅ Docker genrule | - |
| sonic-stp | ✅ dpkg-buildpackage | ✅ Docker genrule | - |
| sonic-swss | ✅ dpkg-buildpackage | ✅ Docker genrule | - |
| FRR | ✅ configure_make | ❌ BUILD exists, not tested | Need Docker genrule |
| snmpd | ✅ make_debs | ❌ Not a submodule | Need dget-style like libnl3 |
| lldpd | ✅ make_debs | ❌ BUILD exists, not tested | Need submodule init |
| redis | ✅ from source | ❌ Using Debian package | Acceptable (same version) |
| libyang | ✅ from source | ❌ Using Debian libyang2 | SONiC patches missing |
| protobuf | ✅ from source | ❌ Using Debian package | Acceptable |
| grpc | ✅ from source | ❌ Not built | Need if gRPC version matters |
| thrift | ✅ from source | ❌ Not built | Need if thrift version matters |
| gobgp | ✅ go build | ❌ BUILD exists, not tested | Need Go build |
| sonic-gnmi | ✅ go + dpkg | ❌ BUILD exists, not tested | Need Go + dpkg |
| sonic-mgmt-common | ✅ dpkg-buildpackage | ❌ BUILD exists, not tested | Need submodule init |
| sonic-mgmt-framework | ✅ dpkg-buildpackage | ❌ BUILD exists, not tested | Need submodule init |
| sonic-utilities | ✅ python wheel | ❌ BUILD exists, not tested | Python wheel |
| sonic-host-services | ✅ python wheel | ❌ BUILD exists, not tested | Python wheel |
| sonic-config-engine | ✅ python wheel | ❌ Not built | Need src/ |
| sonic-py-common | ✅ python wheel | ❌ Not built | Need src/ |
| sonic-yang-models | ✅ python wheel | ❌ Not built | Need src/ |
| sonic-yang-mgmt | ✅ python wheel | ❌ Not built | Need src/ |
| sonic-platform-common | ✅ python wheel | ❌ Not built | Need src/ |
| systemd-sonic-generator | ✅ make | ❌ Not built | System service |
| sonic-device-data | ✅ dpkg | ❌ Not built | Platform data |
| All platform vendor modules | ✅ from binary blobs | ❌ Not built | Broadcom SAI SDK |

### Docker Image Gaps

| Image | Make | Bazel | Notes |
|---|---|---|---|
| docker-orchagent | ✅ | ✅ Docker genrule | Real 7.3 MB orchagent |
| docker-database | ✅ | ✅ Hermetic | @bookworm packages |
| docker-teamd | ✅ | ✅ Hermetic | |
| docker-nat | ✅ | ✅ Hermetic | |
| docker-sflow | ✅ | ✅ Hermetic | |
| docker-stp | ✅ | ✅ Hermetic | |
| docker-iccpd | ✅ | ✅ Hermetic | |
| docker-router-advertiser | ✅ | ✅ Hermetic | |
| docker-basic_router | ✅ | ✅ Hermetic | |
| docker-dhcp-relay | ✅ | ✅ Hermetic | |
| docker-eventd | ✅ | ✅ Hermetic | |
| docker-platform-monitor | ✅ | ✅ Hermetic | |
| docker-sysmgr | ✅ | ✅ Hermetic | |
| docker-sonic-mgmt-framework | ✅ | ✅ Hermetic | |
| docker-fpm-frr | ✅ | ⚠️ Partial | apt hermetic, frr .deb TODO |
| docker-snmp | ✅ | ⚠️ Partial | apt hermetic, snmpd .deb TODO |
| docker-lldp | ✅ | ❌ Old pattern | Needs pip wheel fix |
| docker-macsec | ✅ | ⚠️ Partial | apt hermetic, wpa .deb TODO |
| docker-sonic-gnmi | ✅ | ❌ Old pattern | Needs mgmt-common .deb |
| docker-sonic-telemetry | ✅ | ❌ Old pattern | Chains on gnmi |
| docker-sonic-bmp | ✅ | ⚠️ Partial | Needs sonic-bmp .deb |
| docker-mux | ✅ | ❌ Old pattern | Needs linkmgrd .deb |
| docker-pde | ✅ | ⚠️ Partial | Needs platform-pde .deb |
| docker-sonic-p4rt | ✅ | ❌ Old pattern | Needs p4rt .deb |
| docker-syncd-* | ✅ | ❌ Not started | Vendor SAI containers |
| docker-sonic-vs | ✅ | ❌ Not started | VS all-in-one |

### Test Gaps

| Component | Make Tests | Bazel Tests | Files |
|---|---|---|---|
| sonic-swss-common | ✅ gtest (40 files) | ❌ None | Need cc_test targets |
| sonic-sairedis | ✅ gtest + vslib (238 files) | ❌ None | Need cc_test targets |
| sonic-swss | ✅ gtest + pytest (178 files) | ❌ None | Need cc_test + py_test |
| sonic-utilities | ✅ pytest | ❌ None | Need py_test targets |
| sonic-host-services | ✅ pytest | ❌ None | Need py_test targets |
| docker integration | ✅ vs-test pipeline | ❌ None | Need docker-sonic-vs |

### ONIE Image Gaps

| Component | Make | Bazel | Notes |
|---|---|---|---|
| Kernel | ✅ | ⚠️ CI building | cpupower fix in progress |
| Module filtering | ✅ | ✅ rule exists | Not tested end-to-end |
| Rootfs assembly | ✅ | ✅ with stubs | OCI layer dedup |
| ONIE sharch header | ✅ | ✅ adopted from sonic-bazel | SHA-1 verification |
| Aboot .swi | ✅ | ✅ rule adopted | Not tested |
| sonic-broadcom.bin | ✅ ~1 GB | ❌ Not complete | Needs kernel + all services |
| Size budget (< 400 MB) | ❌ ~1 GB | Target ~324 MB | slim_apt_layer + dedup |
