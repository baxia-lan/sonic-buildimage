# sonic-syseepromd (SONiC Syseeprom gathering daemon) Debian package

# SONIC_SYSEEPROMD_PY2 package

SONIC_SYSEEPROMD_PY2 = sonic_syseepromd-1.0-py2-none-any.whl
$(SONIC_SYSEEPROMD_PY2)_SRC_PATH = $(SRC_PATH)/sonic-platform-daemons/sonic-syseepromd
$(SONIC_SYSEEPROMD_PY2)_DEPENDS = $(SONIC_PY_COMMON_PY2) $(SONIC_PLATFORM_COMMON_PY2)
$(SONIC_SYSEEPROMD_PY2)_DEBS_DEPENDS = $(LIBSWSSCOMMON) $(PYTHON_SWSSCOMMON)
$(SONIC_SYSEEPROMD_PY2)_PYTHON_VERSION = 2
SONIC_PYTHON_WHEELS += $(SONIC_SYSEEPROMD_PY2)

# SONIC_SYSEEPROMD_PY3 package

SONIC_SYSEEPROMD_PY3 = sonic_syseepromd-1.0-py3-none-any.whl
$(SONIC_SYSEEPROMD_PY3)_SRC_PATH = $(SRC_PATH)/sonic-platform-daemons/sonic-syseepromd
$(SONIC_SYSEEPROMD_PY3)_DEPENDS = $(SONIC_PY_COMMON_PY3) $(SONIC_PLATFORM_COMMON_PY3)
$(SONIC_SYSEEPROMD_PY3)_DEBS_DEPENDS = $(LIBSWSSCOMMON) $(PYTHON3_SWSSCOMMON)
$(SONIC_SYSEEPROMD_PY3)_PYTHON_VERSION = 3
SONIC_PYTHON_WHEELS += $(SONIC_SYSEEPROMD_PY3)
