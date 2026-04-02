"""Shared platform and installer metadata for the SONiC Phase 5 migration."""

COMMON_ARCH_AMD64 = ["amd64"]
COMMON_ARCH_ARM64 = ["arm64"]
COMMON_ARCH_MULTI_MRVL = ["amd64", "arm64", "armhf"]

STANDARD_INSTALLER_DOCKERS = ["SONIC_INSTALL_DOCKER_IMAGES"]
DEBUG_CONDITIONAL_INSTALLER_DOCKERS = [
    "SONIC_INSTALL_DOCKER_IMAGES",
    "SONIC_INSTALL_DOCKER_DBG_IMAGES",
]
KVM_RECOVERY_FILES = [
    "ONIE_RECOVERY_IMAGE",
    "ONIE_RECOVERY_KVM_4ASIC_IMAGE",
    "ONIE_RECOVERY_KVM_6ASIC_IMAGE",
]
NON_HERMETIC_INSTALLER_NOTES = [
    "Legacy concrete installer assembly still lives in build_debian.sh and build_image.sh and remains non-hermetic.",
    "This Bazel target owns the installer composition graph and compatibility export surface before the final concrete builder replacement.",
]

BROADCOM_LAZY_INSTALLS = [
    "ARISTA_PLATFORM_MODULE_ALL",
    "DELL_S6000_PLATFORM_MODULE",
    "DELL_Z9264F_PLATFORM_MODULE",
    "DELL_S5212F_PLATFORM_MODULE",
    "DELL_S5224F_PLATFORM_MODULE",
    "DELL_S5232F_PLATFORM_MODULE",
    "DELL_S5248F_PLATFORM_MODULE",
    "DELL_S5448F_PLATFORM_MODULE",
    "DELL_Z9332F_PLATFORM_MODULE",
    "DELL_Z9432F_PLATFORM_MODULE",
    "DELL_S5296F_PLATFORM_MODULE",
    "DELL_Z9100_PLATFORM_MODULE",
    "DELL_S6100_PLATFORM_MODULE",
    "DELL_N3248PXE_PLATFORM_MODULE",
    "DELL_N3248TE_PLATFORM_MODULE",
    "DELL_E3224F_PLATFORM_MODULE",
    "DELL_Z9664F_PLATFORM_MODULE",
    "INGRASYS_S8900_54XC_PLATFORM_MODULE",
    "INGRASYS_S8900_64XC_PLATFORM_MODULE",
    "INGRASYS_S9100_PLATFORM_MODULE",
    "INGRASYS_S8810_32Q_PLATFORM_MODULE",
    "INGRASYS_S9200_64X_PLATFORM_MODULE",
    "ACCTON_AS7712_32X_PLATFORM_MODULE",
    "ACCTON_AS5712_54X_PLATFORM_MODULE",
    "ACCTON_AS7816_64X_PLATFORM_MODULE",
    "ACCTON_AS7716_32X_PLATFORM_MODULE",
    "ACCTON_AS7312_54X_PLATFORM_MODULE",
    "ACCTON_AS7326_56X_PLATFORM_MODULE",
    "ACCTON_AS7716_32XB_PLATFORM_MODULE",
    "ACCTON_AS6712_32X_PLATFORM_MODULE",
    "ACCTON_AS7726_32X_PLATFORM_MODULE",
    "ACCTON_AS4630_54PE_PLATFORM_MODULE",
    "ACCTON_AS4630_54TE_PLATFORM_MODULE",
    "ACCTON_MINIPACK_PLATFORM_MODULE",
    "ACCTON_AS5812_54X_PLATFORM_MODULE",
    "ACCTON_AS5812_54T_PLATFORM_MODULE",
    "ACCTON_AS5835_54X_PLATFORM_MODULE",
    "ACCTON_AS9716_32D_PLATFORM_MODULE",
    "ACCTON_AS9726_32D_PLATFORM_MODULE",
    "ACCTON_AS5835_54T_PLATFORM_MODULE",
    "ACCTON_AS7312_54XS_PLATFORM_MODULE",
    "ACCTON_AS7315_27XB_PLATFORM_MODULE",
    "INVENTEC_D7032Q28B_PLATFORM_MODULE",
    "INVENTEC_D7054Q28B_PLATFORM_MODULE",
    "INVENTEC_D7264Q28B_PLATFORM_MODULE",
    "INVENTEC_D6356_PLATFORM_MODULE",
    "INVENTEC_D6332_PLATFORM_MODULE",
    "CEL_DX010_PLATFORM_MODULE",
    "CEL_HALIBURTON_PLATFORM_MODULE",
    "CEL_SEASTONE2_PLATFORM_MODULE",
    "CEL_DS3000_PLATFORM_MODULE",
    "CEL_DS1000_PLATFORM_MODULE",
    "CEL_QUESTONE2_PLATFORM_MODULE",
    "CEL_SILVERSTONE_V2_PLATFORM_MODULE",
    "CEL_DS2000_PLATFORM_MODULE",
    "DELTA_AG9032V1_PLATFORM_MODULE",
    "DELTA_AG9064_PLATFORM_MODULE",
    "DELTA_AG5648_PLATFORM_MODULE",
    "DELTA_ET6248BRB_PLATFORM_MODULE",
    "QUANTA_IX1B_32X_PLATFORM_MODULE",
    "QUANTA_IX7_32X_PLATFORM_MODULE",
    "QUANTA_IX7_BWDE_32X_PLATFORM_MODULE",
    "QUANTA_IX8_56X_PLATFORM_MODULE",
    "QUANTA_IX8A_BWDE_56X_PLATFORM_MODULE",
    "QUANTA_IX8C_56X_PLATFORM_MODULE",
    "QUANTA_IX9_32X_PLATFORM_MODULE",
    "MITAC_LY1200_32X_PLATFORM_MODULE",
    "ALPHANETWORKS_SNH60A0_320FV2_PLATFORM_MODULE",
    "ALPHANETWORKS_SNH60B0_640F_PLATFORM_MODULE",
    "ALPHANETWORKS_SNJ60D0_320F_PLATFORM_MODULE",
    "ALPHANETWORKS_BES2348T_PLATFORM_MODULE",
    "BRCM_XLR_GTS_PLATFORM_MODULE",
    "DELTA_AG9032V2A_PLATFORM_MODULE",
    "JUNIPER_QFX5210_PLATFORM_MODULE",
    "CEL_SILVERSTONE_PLATFORM_MODULE",
    "JUNIPER_QFX5200_PLATFORM_MODULE",
    "DELTA_AGC032_PLATFORM_MODULE",
    "RUIJIE_B6510_48VS8CQ_PLATFORM_MODULE",
    "RAGILE_RA_B6510_48V8C_PLATFORM_MODULE",
    "NOKIA_IXR7250_PLATFORM_MODULE",
    "NOKIA_IXR7220D4_PLATFORM_MODULE",
    "NOKIA_IXR7220H3_PLATFORM_MODULE",
    "NOKIA_IXR7220H4_32D_PLATFORM_MODULE",
    "NOKIA_IXR7220H4_64D_PLATFORM_MODULE",
    "NOKIA_IXR7220H5_64O_PLATFORM_MODULE",
    "NOKIA_IXR7220H5_64D_PLATFORM_MODULE",
    "NOKIA_IXR7220H5_32D_PLATFORM_MODULE",
    "NOKIA_IXR7220H6_64_PLATFORM_MODULE",
    "NOKIA_IXR7220H6_128_PLATFORM_MODULE",
    "NOKIA_IXR7250X1B_PLATFORM_MODULE",
    "NOKIA_IXR7250X3B_PLATFORM_MODULE",
    "NOKIA_IXR7250X4_PLATFORM_MODULE",
    "TENCENT_TCS8400_PLATFORM_MODULE",
    "TENCENT_TCS9400_PLATFORM_MODULE",
    "UFISPACE_S9311_64D_PLATFORM_MODULE",
    "UFISPACE_S6301_56ST_PLATFORM_MODULE",
    "UFISPACE_S7801_54XS_PLATFORM_MODULE",
    "UFISPACE_S8901_54XC_PLATFORM_MODULE",
    "UFISPACE_S9110_32X_PLATFORM_MODULE",
    "UFISPACE_S9300_32D_PLATFORM_MODULE",
    "UFISPACE_S9301_32D_PLATFORM_MODULE",
    "UFISPACE_S9301_32DB_PLATFORM_MODULE",
    "UFISPACE_S9321_64E_PLATFORM_MODULE",
    "UFISPACE_S9321_64EO_PLATFORM_MODULE",
    "NEXTHOP_COMMON_PLATFORM_MODULE",
    "NEXTHOP_KOMODO_PLATFORM_MODULE",
    "NEXTHOP_4010_PLATFORM_MODULE",
    "NEXTHOP_4010_R0_PLATFORM_MODULE",
    "NEXTHOP_4010_R1_PLATFORM_MODULE",
    "NEXTHOP_4020_R0_PLATFORM_MODULE",
    "NEXTHOP_4220_PLATFORM_MODULE",
    "NEXTHOP_4220_R0_PLATFORM_MODULE",
    "NEXTHOP_5010_PLATFORM_MODULE",
    "NEXTHOP_5010_R0_PLATFORM_MODULE",
    "MICAS_M2_W6510_48V8C_PLATFORM_MODULE",
    "MICAS_M2_W6510_48GT4V_PLATFORM_MODULE",
    "MICAS_M2_W6520_24DC8QC_PLATFORM_MODULE",
    "MICAS_M2_W6940_128QC_PLATFORM_MODULE",
    "MICAS_M2_W6930_64QC_PLATFORM_MODULE",
    "MICAS_M2_W6940_64OC_PLATFORM_MODULE",
    "MICAS_M2_W6920_32QC2X_PLATFORM_MODULE",
    "MICAS_M2_W6510_32C_PLATFORM_MODULE",
    "MICAS_M2_W6520_48C8QC_PLATFORM_MODULE",
    "SMCI_SSE_T8164_PLATFORM_MODULE",
    "SMCI_SSE_T8196_PLATFORM_MODULE",
]

BROADCOM_PLATFORM = {
    "legacy_artifact": "broadcom-platform-payloads",
    "source_path": "platform/broadcom",
    "source_makefiles": [
        "platform/broadcom/rules.mk",
        "platform/broadcom/one-image.mk",
        "platform/broadcom/raw-image.mk",
        "platform/broadcom/one-aboot.mk",
    ],
    "machine": "broadcom",
    "platform_name": "broadcom",
    "dependent_machines": ["broadcom-dnx", "broadcom-legacy-th"],
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "PDDF_PLATFORM_MODULE",
        "SYSTEMD_SONIC_GENERATOR",
        "FLASHROM",
        "BRCM_OPENNSL_KERNEL",
        "BRCM_DNX_OPENNSL_KERNEL",
        "BRCM_LEGACY_TH_OPENNSL_KERNEL",
        "ARISTA_PLATFORM_MODULE_PYTHON3",
        "ARISTA_PLATFORM_MODULE_DRIVERS",
        "ARISTA_PLATFORM_MODULE_LIBS",
        "ARISTA_PLATFORM_MODULE",
    ],
    "legacy_lazy_installs": BROADCOM_LAZY_INSTALLS,
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "BROADCOM_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

BROADCOM_ONIE = {
    "legacy_artifact": "sonic-broadcom.bin",
    "source_path": "platform/broadcom",
    "source_makefiles": ["platform/broadcom/one-image.mk"],
    "machine": "broadcom",
    "platform_name": "broadcom",
    "dependent_machines": ["broadcom-dnx", "broadcom-legacy-th"],
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": [
        "PDDF_PLATFORM_MODULE",
        "SYSTEMD_SONIC_GENERATOR",
        "FLASHROM",
    ],
    "legacy_lazy_installs": BROADCOM_LAZY_INSTALLS,
    "legacy_lazy_build_installs": [
        "BRCM_OPENNSL_KERNEL",
        "BRCM_DNX_OPENNSL_KERNEL",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

BROADCOM_RAW = {
    "legacy_artifact": "sonic-broadcom.raw",
    "source_path": "platform/broadcom",
    "source_makefiles": ["platform/broadcom/raw-image.mk"],
    "machine": "broadcom",
    "platform_name": "broadcom",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "raw",
    "legacy_installs": [
        "BRCM_OPENNSL_KERNEL",
        "SYSTEMD_SONIC_GENERATOR",
        "FLASHROM",
    ],
    "legacy_lazy_installs": BROADCOM_LAZY_INSTALLS,
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_RAW_IMAGE",
        "migration_role": "raw_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

BROADCOM_ABOOT = {
    "legacy_artifact": "sonic-aboot-broadcom.swi",
    "source_path": "platform/broadcom",
    "source_makefiles": ["platform/broadcom/one-aboot.mk"],
    "machine": "broadcom",
    "platform_name": "broadcom",
    "dependent_machines": ["broadcom-dnx", "broadcom-legacy-th"],
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "aboot",
    "legacy_installs": [
        "FLASHROM",
        "SYSTEMD_SONIC_GENERATOR",
        "ARISTA_PLATFORM_MODULE_PYTHON3",
        "ARISTA_PLATFORM_MODULE_DRIVERS",
        "ARISTA_PLATFORM_MODULE_LIBS",
        "ARISTA_PLATFORM_MODULE",
    ],
    "legacy_lazy_build_installs": [
        "BRCM_OPENNSL_KERNEL",
        "BRCM_DNX_OPENNSL_KERNEL",
        "BRCM_LEGACY_TH_OPENNSL_KERNEL",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_ABOOT_IMAGE",
        "migration_role": "aboot_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES + [
        "Optional PHY_CREDO, ARISTA_FWUTIL, and ARISTA_FIRMWARE payloads remain conditional migration inputs.",
    ],
}

GENERIC_PLATFORM = {
    "legacy_artifact": "generic-platform-payloads",
    "source_path": "platform/generic",
    "source_makefiles": [
        "platform/generic/onie-image.mk",
        "platform/generic/aboot-image.mk",
    ],
    "machine": "generic",
    "platform_name": "generic",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "metadata": {
        "legacy_name": "GENERIC_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

GENERIC_ONIE = {
    "legacy_artifact": "sonic-generic.bin",
    "source_path": "platform/generic",
    "source_makefiles": ["platform/generic/onie-image.mk"],
    "machine": "generic",
    "platform_name": "generic",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "metadata": {
        "legacy_name": "SONIC_GENERIC_ONIE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

GENERIC_ABOOT = {
    "legacy_artifact": "sonic-aboot-generic.swi",
    "source_path": "platform/generic",
    "source_makefiles": ["platform/generic/aboot-image.mk"],
    "machine": "generic",
    "platform_name": "generic",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "aboot",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "metadata": {
        "legacy_name": "SONIC_GENERIC_ABOOT_IMAGE",
        "migration_role": "aboot_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VS_PLATFORM = {
    "legacy_artifact": "vs-platform-payloads",
    "source_path": "platform/vs",
    "source_makefiles": [
        "platform/vs/one-image.mk",
        "platform/vs/raw-image.mk",
        "platform/vs/kvm-image.mk",
    ],
    "machine": "vs",
    "platform_name": "vs",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": ["VS_PLATFORM_MODULE"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "VS_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VS_ONIE = {
    "legacy_artifact": "sonic-vs.bin",
    "source_path": "platform/vs",
    "source_makefiles": ["platform/vs/one-image.mk"],
    "machine": "vs",
    "platform_name": "vs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": ["VS_PLATFORM_MODULE"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VS_RAW = {
    "legacy_artifact": "sonic-vs.raw",
    "source_path": "platform/vs",
    "source_makefiles": ["platform/vs/raw-image.mk"],
    "machine": "vs",
    "platform_name": "vs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "raw",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_RAW_IMAGE",
        "migration_role": "raw_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VS_KVM = {
    "legacy_artifact": "sonic-vs.img.gz",
    "source_path": "platform/vs",
    "source_makefiles": ["platform/vs/kvm-image.mk"],
    "machine": "vs",
    "platform_name": "vs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "kvm",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": ["VS_PLATFORM_MODULE"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "files": KVM_RECOVERY_FILES,
    "metadata": {
        "legacy_name": "SONIC_KVM_IMAGE",
        "migration_role": "kvm_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

ALPINEVS_PLATFORM = {
    "legacy_artifact": "alpinevs-platform-payloads",
    "source_path": "platform/alpinevs",
    "source_makefiles": [
        "platform/alpinevs/one-image.mk",
        "platform/alpinevs/raw-image.mk",
        "platform/alpinevs/kvm-image.mk",
    ],
    "machine": "alpinevs",
    "platform_name": "alpinevs",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "ALPINE_CONFIG",
        "ALPINE_INIT",
        "ALPINE_DEVICE",
        "GENL_PACKET_MODULE",
        "PKT_HANDLER",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "ALPINEVS_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

ALPINEVS_ONIE = {
    "legacy_artifact": "sonic-alpinevs.bin",
    "source_path": "platform/alpinevs",
    "source_makefiles": ["platform/alpinevs/one-image.mk"],
    "machine": "alpinevs",
    "platform_name": "alpinevs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "ALPINE_CONFIG",
        "ALPINE_INIT",
        "ALPINE_DEVICE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

ALPINEVS_RAW = {
    "legacy_artifact": "sonic-alpinevs.raw",
    "source_path": "platform/alpinevs",
    "source_makefiles": ["platform/alpinevs/raw-image.mk"],
    "machine": "alpinevs",
    "platform_name": "alpinevs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "raw",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "ALPINE_CONFIG",
        "ALPINE_INIT",
        "ALPINE_DEVICE",
    ],
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_RAW_IMAGE",
        "migration_role": "raw_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

ALPINEVS_KVM = {
    "legacy_artifact": "sonic-alpinevs.img.gz",
    "source_path": "platform/alpinevs",
    "source_makefiles": ["platform/alpinevs/kvm-image.mk"],
    "machine": "alpinevs",
    "platform_name": "alpinevs",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "kvm",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "GENL_PACKET_MODULE",
        "PKT_HANDLER",
        "ALPINE_CONFIG",
        "ALPINE_INIT",
        "ALPINE_DEVICE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "files": KVM_RECOVERY_FILES,
    "metadata": {
        "legacy_name": "SONIC_KVM_IMAGE",
        "migration_role": "kvm_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VPP_PLATFORM = {
    "legacy_artifact": "vpp-platform-payloads",
    "source_path": "platform/vpp",
    "source_makefiles": [
        "platform/vpp/rules/one-image.mk",
        "platform/vpp/rules/raw-image.mk",
        "platform/vpp/rules/kvm-image.mk",
    ],
    "machine": "vpp",
    "platform_name": "vpp",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "VPP_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "VPP_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VPP_ONIE = {
    "legacy_artifact": "sonic-vpp.bin",
    "source_path": "platform/vpp",
    "source_makefiles": ["platform/vpp/rules/one-image.mk"],
    "machine": "vpp",
    "platform_name": "vpp",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "VPP_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VPP_RAW = {
    "legacy_artifact": "sonic-vpp.raw",
    "source_path": "platform/vpp",
    "source_makefiles": ["platform/vpp/rules/raw-image.mk"],
    "machine": "vpp",
    "platform_name": "vpp",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "raw",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "VPP_PLATFORM_MODULE",
    ],
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_RAW_IMAGE",
        "migration_role": "raw_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

VPP_KVM = {
    "legacy_artifact": "sonic-vpp.img.gz",
    "source_path": "platform/vpp",
    "source_makefiles": ["platform/vpp/rules/kvm-image.mk"],
    "machine": "vpp",
    "platform_name": "vpp",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "kvm",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "VPP_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "files": KVM_RECOVERY_FILES,
    "metadata": {
        "legacy_name": "SONIC_KVM_IMAGE",
        "migration_role": "kvm_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

ASPEED_PLATFORM = {
    "legacy_artifact": "aspeed-platform-payloads",
    "source_path": "platform/aspeed",
    "source_makefiles": ["platform/aspeed/one-image.mk"],
    "machine": "aspeed",
    "platform_name": "aspeed",
    "configured_arches": COMMON_ARCH_ARM64,
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": [
        "ASPEED_EVB_AST2700_PLATFORM_MODULE",
        "NEXTHOP_COMMON_PLATFORM_MODULE",
        "ASPEED_NEXTHOP_B27_PLATFORM_MODULE",
    ],
    "legacy_docker_images": [
        "DOCKER_DATABASE",
        "DOCKER_GNMI",
        "DOCKER_PLATFORM_MONITOR",
        "DOCKER_LLDP",
        "DOCKER_TELEMETRY",
        "DOCKER_SYSMGR",
    ],
    "metadata": {
        "legacy_name": "ASPEED_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES + [
        "Legacy Make filters out a large set of local packages and service images for this embedded platform.",
    ],
}

ASPEED_ONIE = {
    "legacy_artifact": "sonic-aspeed-arm64.bin",
    "source_path": "platform/aspeed",
    "source_makefiles": ["platform/aspeed/one-image.mk"],
    "machine": "aspeed",
    "platform_name": "aspeed",
    "configured_arches": COMMON_ARCH_ARM64,
    "installer_format": "onie",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": [
        "ASPEED_EVB_AST2700_PLATFORM_MODULE",
        "NEXTHOP_COMMON_PLATFORM_MODULE",
        "ASPEED_NEXTHOP_B27_PLATFORM_MODULE",
    ],
    "legacy_docker_images": [
        "DOCKER_DATABASE",
        "DOCKER_GNMI",
        "DOCKER_PLATFORM_MONITOR",
        "DOCKER_LLDP",
        "DOCKER_TELEMETRY",
        "DOCKER_SYSMGR",
    ],
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": ASPEED_PLATFORM["notes"],
}

CENTEC_PLATFORM = {
    "legacy_artifact": "centec-platform-payloads",
    "source_path": "platform/centec",
    "source_makefiles": ["platform/centec/one-image.mk"],
    "machine": "centec",
    "platform_name": "centec",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": [
        "CENTEC_E582_48X6Q_PLATFORM_MODULE",
        "CENTEC_E582_48X2Q4Z_PLATFORM_MODULE",
        "EMBEDWAY_ES6220_PLATFORM_MODULE",
        "CENTEC_V682_48Y8C_D_PLATFORM_MODULE",
        "CENTEC_V682_48Y8C_PLATFORM_MODULE",
        "CENTEC_V682_48X8C_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "CENTEC_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

CENTEC_ONIE = {
    "legacy_artifact": "sonic-centec.bin",
    "source_path": "platform/centec",
    "source_makefiles": ["platform/centec/one-image.mk"],
    "machine": "centec",
    "platform_name": "centec",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": CENTEC_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

CENTEC_ARM64_PLATFORM = {
    "legacy_artifact": "centec-arm64-platform-payloads",
    "source_path": "platform/centec-arm64",
    "source_makefiles": ["platform/centec-arm64/one-image.mk"],
    "machine": "centec-arm64",
    "platform_name": "centec-arm64",
    "configured_arches": COMMON_ARCH_ARM64,
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "TSINGMA_BSP_MODULE",
    ],
    "legacy_lazy_installs": [
        "CENTEC_E530_48T4X_P_PLATFORM_MODULE",
        "CENTEC_E530_24X2C_PLATFORM_MODULE",
        "CENTEC_E530_48S4X_PLATFORM_MODULE",
        "CENTEC_E530_24X2Q_PLATFORM_MODULE",
        "FS_S5800_48T4S_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "CENTEC_ARM64_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

CENTEC_ARM64_ONIE = {
    "legacy_artifact": "sonic-centec-arm64.bin",
    "source_path": "platform/centec-arm64",
    "source_makefiles": ["platform/centec-arm64/one-image.mk"],
    "machine": "centec-arm64",
    "platform_name": "centec-arm64",
    "configured_arches": COMMON_ARCH_ARM64,
    "installer_format": "onie",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "TSINGMA_BSP_MODULE",
    ],
    "legacy_lazy_installs": CENTEC_ARM64_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

CLOUNIX_PLATFORM = {
    "legacy_artifact": "clounix-platform-payloads",
    "source_path": "platform/clounix",
    "source_makefiles": ["platform/clounix/one-image.mk"],
    "machine": "clounix",
    "platform_name": "clounix",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "CLOUNIX_MODULE",
        "CLX_UTILS",
        "SYSTEMD_SONIC_GENERATOR",
    ],
    "legacy_lazy_installs": ["PEGATRON_FN8656_BNF_PLATFORM_MODULE"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "CLOUNIX_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

CLOUNIX_ONIE = {
    "legacy_artifact": "sonic-clounix.bin",
    "source_path": "platform/clounix",
    "source_makefiles": ["platform/clounix/one-image.mk"],
    "machine": "clounix",
    "platform_name": "clounix",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": CLOUNIX_PLATFORM["legacy_installs"],
    "legacy_lazy_installs": CLOUNIX_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

MRVL_PRESTERA_PLATFORM = {
    "legacy_artifact": "marvell-prestera-platform-payloads",
    "source_path": "platform/marvell-prestera",
    "source_makefiles": ["platform/marvell-prestera/one-image.mk"],
    "machine": "marvell-prestera",
    "platform_name": "marvell-prestera",
    "configured_arches": COMMON_ARCH_MULTI_MRVL,
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "MRVL_PRESTERA_DEB",
    ],
    "legacy_lazy_installs": [
        "NOKIA_7215_PLATFORM",
        "AC5X_RD98DX35xx_PLATFORM",
        "AC5X_RD98DX35xxCN9131_PLATFORM",
        "AC5P_RD98DX45xxCN9131_PLATFORM",
        "FALCON_DB98CX8580_32CD_PLATFORM",
        "FALCON_DB98CX8540_16CD_PLATFORM",
        "FALCON_DB98CX8514_10CC_PLATFORM",
        "FALCON_DB98CX8522_10CC_PLATFORM",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "MRVL_PRESTERA_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES + [
        "Legacy Make branches payload membership by configured architecture; this manifest records the full arch-qualified surface.",
    ],
}

MRVL_PRESTERA_ONIE = {
    "legacy_artifact": "sonic-marvell-prestera-$(CONFIGURED_ARCH).bin",
    "lock_output_name": "sonic-marvell-prestera.installer.lock.json",
    "source_path": "platform/marvell-prestera",
    "source_makefiles": ["platform/marvell-prestera/one-image.mk"],
    "machine": "marvell-prestera",
    "platform_name": "marvell-prestera",
    "configured_arches": COMMON_ARCH_MULTI_MRVL,
    "installer_format": "onie",
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "MRVL_PRESTERA_DEB",
    ],
    "legacy_lazy_installs": MRVL_PRESTERA_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": MRVL_PRESTERA_PLATFORM["notes"],
}

MRVL_TERALYNX_PLATFORM = {
    "legacy_artifact": "marvell-teralynx-platform-payloads",
    "source_path": "platform/marvell-teralynx",
    "source_makefiles": ["platform/marvell-teralynx/one-image.mk"],
    "machine": "marvell-teralynx",
    "platform_name": "marvell-teralynx",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "SYSTEMD_SONIC_GENERATOR",
        "MRVL_TERALYNX_DRV",
        "MRVL_TERALYNX_DEB",
        "PDDF_PLATFORM_MODULE",
    ],
    "legacy_lazy_installs": [
        "CEL_MIDSTONE_200I_PLATFORM_MODULE",
        "DELTA_PLATFORM_MODULE",
        "NETBERG_AURORA_715_PLATFORM_MODULE",
        "SMCI_SSE_T7132S_PLATFORM_MODULE",
        "WISTRON_PLATFORM_MODULE",
        "TL10_DBMVTX9180_PLATFORM",
    ],
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "MRVL_TERALYNX_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

MRVL_TERALYNX_ONIE = {
    "legacy_artifact": "sonic-marvell-teralynx.bin",
    "source_path": "platform/marvell-teralynx",
    "source_makefiles": ["platform/marvell-teralynx/one-image.mk"],
    "machine": "marvell-teralynx",
    "platform_name": "marvell-teralynx",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": MRVL_TERALYNX_PLATFORM["legacy_installs"],
    "legacy_lazy_installs": MRVL_TERALYNX_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": STANDARD_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

MELLANOX_PLATFORM = {
    "legacy_artifact": "mellanox-platform-payloads",
    "source_path": "platform/mellanox",
    "source_makefiles": ["platform/mellanox/one-image.mk"],
    "machine": "mellanox",
    "platform_name": "mellanox",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "SX_KERNEL",
        "KERNEL_MFT",
        "MFT_OEM",
        "MFT",
        "MFT_FWTRACE_CFG",
        "MLNX_HW_MANAGEMENT",
        "MLNX_RSHIM",
        "SYSTEMD_SONIC_GENERATOR",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "files": [
        "MLNX_FILES",
        "MLNX_CPLD_ARCHIVES",
    ],
    "legacy_wheel_deps": ["MELLANOX_FW_MANAGER"],
    "metadata": {
        "legacy_name": "MELLANOX_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

MELLANOX_ONIE = {
    "legacy_artifact": "sonic-mellanox.bin",
    "source_path": "platform/mellanox",
    "source_makefiles": ["platform/mellanox/one-image.mk"],
    "machine": "mellanox",
    "platform_name": "mellanox",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": MELLANOX_PLATFORM["legacy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "legacy_wheel_deps": ["MELLANOX_FW_MANAGER"],
    "files": [
        "MLNX_FILES",
        "MLNX_CPLD_ARCHIVES",
    ],
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

NEPHOS_PLATFORM = {
    "legacy_artifact": "nephos-platform-payloads",
    "source_path": "platform/nephos",
    "source_makefiles": ["platform/nephos/one-image.mk"],
    "machine": "nephos",
    "platform_name": "nephos",
    "configured_arches": COMMON_ARCH_AMD64,
    "legacy_installs": [
        "NEPHOS_MODULE",
        "SYSTEMD_SONIC_GENERATOR",
    ],
    "legacy_lazy_installs": [
        "INGRASYS_S9130_32X_PLATFORM_MODULE",
        "INGRASYS_S9230_64X_PLATFORM_MODULE",
        "ACCTON_AS7116_54X_PLATFORM_MODULE",
        "CIG_CS6436_56P_PLATFORM_MODULE",
        "CIG_CS6436_54P_PLATFORM_MODULE",
        "CIG_CS5435_54P_PLATFORM_MODULE",
    ],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "NEPHOS_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

NEPHOS_ONIE = {
    "legacy_artifact": "sonic-nephos.bin",
    "source_path": "platform/nephos",
    "source_makefiles": ["platform/nephos/one-image.mk"],
    "machine": "nephos",
    "platform_name": "nephos",
    "configured_arches": COMMON_ARCH_AMD64,
    "installer_format": "onie",
    "legacy_installs": NEPHOS_PLATFORM["legacy_installs"],
    "legacy_lazy_installs": NEPHOS_PLATFORM["legacy_lazy_installs"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

NOKIA_VS_PLATFORM = {
    "legacy_artifact": "nokia-vs-platform-payloads",
    "source_path": "platform/nokia-vs",
    "source_makefiles": ["platform/nokia-vs/one-image.mk"],
    "machine": "nokia-vs",
    "platform_name": "nokia-vs",
    "configured_arches": COMMON_ARCH_ARM64,
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": ["NOKIA_7215_PLATFORM"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "NOKIA_VS_PLATFORM",
        "migration_role": "platform_payload_manifest",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}

NOKIA_VS_ONIE = {
    "legacy_artifact": "sonic-nokia-vs-$(CONFIGURED_ARCH).bin",
    "lock_output_name": "sonic-nokia-vs.installer.lock.json",
    "source_path": "platform/nokia-vs",
    "source_makefiles": ["platform/nokia-vs/one-image.mk"],
    "machine": "nokia-vs",
    "platform_name": "nokia-vs",
    "configured_arches": COMMON_ARCH_ARM64,
    "installer_format": "onie",
    "legacy_installs": ["SYSTEMD_SONIC_GENERATOR"],
    "legacy_lazy_installs": ["NOKIA_7215_PLATFORM"],
    "legacy_docker_images": DEBUG_CONDITIONAL_INSTALLER_DOCKERS,
    "metadata": {
        "legacy_name": "SONIC_ONE_IMAGE",
        "migration_role": "onie_installer",
        "migration_wave": "phase5_onie",
    },
    "notes": NON_HERMETIC_INSTALLER_NOTES,
}
