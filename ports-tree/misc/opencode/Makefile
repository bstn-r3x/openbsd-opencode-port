# $OpenBSD$

COMMENT =	OpenCode terminal coding assistant (local bootstrap port)

# WIP: local-bootstrap port for validating a ports-framework package/install layout
# using a locally built OpenCode binary while the final distfile/source build strategy
# is implemented.
V =		0.0.0
DISTNAME =	opencode-${V}
PKGNAME =	opencode-${V}
CATEGORIES =	misc

HOMEPAGE =	https://github.com/bstn-r3x/opencode-openbsd

# Target direction (Option 1 selected): source-distfile-based port build.
#
# Planned shape (not implemented yet):
# - fetch OpenCode source distfile(s) + verify via distinfo
# - build inside the ports framework using Bun on OpenBSD
# - install wrapper + libexec binary + docs via do-install
#
# Current blockers for the source-distfile path:
# - no `lang/bun` port in the base OpenBSD ports tree (build dependency gap)
# - no ports module/integration for Bun workspace dependency resolution
# - OpenBSD build host needs node/node-gyp + python3 + gmake for dependency install scripts
# - Bun compile needs a spacious TMPDIR (ENOSPC observed on small /tmp)
# - upstream @opentui/core lacks an OpenBSD optional package; OpenCode fork vendors core-openbsd-x64 payload
# - naive vendoring is too large (measured on bstn: monorepo node_modules ~3.8G; filtered workspace install reduced to ~516M)
#
# This port stays in a local-bootstrap mode for now to validate install layout and
# package behavior through bsd.port.mk while the source-distfile strategy is refined.

# TODO: set maintainer before submission
MAINTAINER =	bstn@example.invalid

# TODO: fill in the actual license / permit knobs
PERMIT_PACKAGE =	Yes

ONLY_FOR_ARCHS =	amd64

DISTFILES =
EXTRACT_ONLY =
NO_EXTRACT =	Yes
NO_BUILD =	Yes
NO_CONFIGURE =	Yes
NO_TEST =	Yes

# Runtime libraries observed from local OpenBSD package validation builds.
WANTLIB +=	c c++ c++abi kvm m pthread

# Maintainer local-bootstrap input (OpenBSD-built OpenCode binary).
OPENCODE_LOCAL_BIN ?=	/srv/opencode-port/opencode/packages/opencode/dist/opencode-openbsd-x64/bin/opencode
.if !exists(${OPENCODE_LOCAL_BIN})
BROKEN =	set OPENCODE_LOCAL_BIN to a built OpenCode binary (default missing: ${OPENCODE_LOCAL_BIN})
.endif

do-install:
	${INSTALL_DATA_DIR} ${PREFIX}/bin
	${INSTALL_DATA_DIR} ${PREFIX}/libexec/opencode
	${INSTALL_DATA_DIR} ${PREFIX}/share/doc/opencode
	${INSTALL_SCRIPT} ${FILESDIR}/opencode ${PREFIX}/bin/opencode
	${INSTALL_DATA} ${OPENCODE_LOCAL_BIN} ${PREFIX}/libexec/opencode/opencode-bin
	chmod 755 ${PREFIX}/libexec/opencode/opencode-bin
	${INSTALL_DATA} ${FILESDIR}/README.txt ${PREFIX}/share/doc/opencode/README.txt
	${INSTALL_DATA} ${FILESDIR}/TROUBLESHOOTING.txt ${PREFIX}/share/doc/opencode/TROUBLESHOOTING.txt

.include <bsd.port.mk>
