# $OpenBSD$

COMMENT =	OpenCode terminal coding assistant

# TODO: replace with a real distfile-backed version once the ports build path is wired.
V =		0.0.0
DISTNAME =	opencode-${V}
PKGNAME =	opencode-${V}
CATEGORIES =	misc

HOMEPAGE =	https://github.com/bstn-r3x/opencode-openbsd

# TODO: set maintainer before submission
MAINTAINER =	bstn@example.invalid

# TODO: fill in the actual license / permit knobs
PERMIT_PACKAGE =	Yes

# TODO: choose a real ports distfile strategy (source tarball vs generated release artifact)
# and populate SITES / EXTRACT_SUFX / distinfo accordingly.

# Runtime libraries observed from local OpenBSD package validation builds.
WANTLIB +=	c c++ c++abi kvm m pthread

# The official ports build/install path is not implemented yet. This skeleton exists to
# track ports-tree metadata and install layout while the framework build strategy is designed.
BROKEN =	work in progress: ports framework build/install steps not implemented yet

NO_TEST =	Yes

# Intended install layout (kept aligned with local pkg_create validation):
#   /usr/local/bin/opencode
#   /usr/local/libexec/opencode/opencode-bin
#   /usr/local/share/doc/opencode/README.txt
#   /usr/local/share/doc/opencode/TROUBLESHOOTING.txt

.include <bsd.port.mk>
