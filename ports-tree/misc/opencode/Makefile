# $OpenBSD$

COMMENT =	OpenCode terminal coding assistant

# WIP: source-distfile prototype for validating an offline ports-framework build
# using published source + vendor distfiles (currently hosted on GitHub Releases).
V =		0.0.1
REVISION =	2
SRC_COMMIT =	8df9f07
DISTNAME =	opencode-source-${SRC_COMMIT}
PKGNAME =	opencode-${V}
CATEGORIES =	misc

HOMEPAGE =	https://github.com/bstn-r3x/opencode-openbsd

# Target direction (Option 1 selected): source-distfile-based port build.
#
# This prototype consumes two published distfiles (currently from GitHub Releases):
# - opencode-${V}-main-src.tar.gz
# - opencode-${V}-main-vendor.tar.gz
#
# The vendor payload (filtered Bun workspace deps + workspace package node_modules symlink dirs)
# makes do-build offline/reproducible on the port host.
#
# Future ports-ready direction:
# - move published distfiles to a stable upstream/release process
# - add lang/bun BUILD_DEPENDS once a Bun port exists
# - finalize license/permit metadata and maintainer
#
# Maintainer prep toolchain requirements (not consumed by do-build here):
# - lang/node
# - node-gyp (currently host wrapper on bstn; no base ports entry confirmed)
# - lang/python/3
# - devel/gmake
# - TMPDIR with >=2GB free (Bun compile ENOSPC observed on small /tmp)

# TODO: set maintainer before submission
MAINTAINER =	bstn@example.invalid

# TODO: fill in the actual license / permit knobs
PERMIT_PACKAGE =	Yes

ONLY_FOR_ARCHS =	amd64

DIST_SUBDIR =	opencode
SITES =	https://github.com/bstn-r3x/openbsd-opencode-port/releases/download/v${V}-main/
SRC_DISTFILE =	opencode-${V}-main-src.tar.gz
VENDOR_DISTFILE =	opencode-${V}-main-vendor.tar.gz
DISTFILES =	${SRC_DISTFILE} \
		${VENDOR_DISTFILE}
EXTRACT_ONLY =
NO_EXTRACT =	Yes
NO_CONFIGURE =	Yes
NO_TEST =	Yes

WRKDIST =	${WRKDIR}/opencode-src

# Runtime libraries observed from local OpenBSD package validation builds.
WANTLIB +=	c c++ c++abi kvm m pthread

# Prototype host tool (future BUILD_DEPENDS target: lang/bun).
BUN_BIN ?=	/srv/opencode-port/bun
.if !exists(${BUN_BIN})
BROKEN =	set BUN_BIN to a Bun binary (prototype host tool; future BUILD_DEPENDS: lang/bun)
.endif

MAKE_ENV +=	TMPDIR=${WRKDIR}/tmp
MAKE_ENV +=	HOME=${WRKDIR}/home
MAKE_ENV +=	OPENCODE_BUILD_FETCH_DEPS=0
MAKE_ENV +=	OPENCODE_REFRESH_MODELS_SNAPSHOT=0
MAKE_ENV +=	OPENCODE_CHANNEL=main
MAKE_ENV +=	OPENCODE_VERSION=0.0.0-main-ports.${SRC_COMMIT}

# Build script already defaults to hermetic snapshot usage and no dependency prefetch.
# Keep --skip-install to avoid any runtime dependency acquisition during do-build.
OPENCODE_BUILD_CMD =	${BUN_BIN} run --cwd packages/opencode script/build.ts --single --skip-install
OPENCODE_BUILT_BIN =	${WRKDIST}/packages/opencode/dist/opencode-openbsd-x64/bin/opencode

# Distfiles are fetched from ${SITES}; local copies in ${DISTDIR}/${DIST_SUBDIR} are also supported.
# Example manual seeding for offline tests:
#   cp <artifacts>/${SRC_DISTFILE} ${DISTDIR}/${DIST_SUBDIR}/
#   cp <artifacts>/${VENDOR_DISTFILE} ${DISTDIR}/${DIST_SUBDIR}/

do-extract:
	rm -rf ${WRKDIST}
	${INSTALL_DATA_DIR} ${WRKDIST}
	cd ${WRKDIST} && tar -xzf ${DISTDIR}/${DIST_SUBDIR}/${SRC_DISTFILE}
	cd ${WRKDIST} && tar -xzf ${DISTDIR}/${DIST_SUBDIR}/${VENDOR_DISTFILE}

do-build:
	${INSTALL_DATA_DIR} ${WRKDIR}/tmp
	${INSTALL_DATA_DIR} ${WRKDIR}/home
	cd ${WRKDIST} && ${SETENV} ${MAKE_ENV} ${OPENCODE_BUILD_CMD}

do-install:
	${INSTALL_DATA_DIR} ${PREFIX}/bin
	${INSTALL_DATA_DIR} ${PREFIX}/libexec/opencode
	${INSTALL_DATA_DIR} ${PREFIX}/share/doc/opencode
	${INSTALL_SCRIPT} ${FILESDIR}/opencode ${PREFIX}/bin/opencode
	${INSTALL_DATA} ${OPENCODE_BUILT_BIN} ${PREFIX}/libexec/opencode/opencode-bin
	chmod 755 ${PREFIX}/libexec/opencode/opencode-bin
	${INSTALL_DATA} ${FILESDIR}/README.txt ${PREFIX}/share/doc/opencode/README.txt
	${INSTALL_DATA} ${FILESDIR}/TROUBLESHOOTING.txt ${PREFIX}/share/doc/opencode/TROUBLESHOOTING.txt
	${INSTALL_DATA} ${FILESDIR}/LICENSE.txt ${PREFIX}/share/doc/opencode/LICENSE.txt
	${INSTALL_DATA} ${FILESDIR}/THIRD-PARTY-NOTICES.txt ${PREFIX}/share/doc/opencode/THIRD-PARTY-NOTICES.txt

.include <bsd.port.mk>
