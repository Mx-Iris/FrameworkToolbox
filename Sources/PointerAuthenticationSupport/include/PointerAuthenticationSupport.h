//
//  PointerAuthenticationSupport.h
//
//  Minimal C shim exposing the arm64e pointer-authentication intrinsics that
//  Swift has no spelling for. Every function degrades to the identity on
//  targets built without pointer authentication (arm64, x86_64), so callers
//  never need to branch on the architecture themselves.
//

#ifndef POINTER_AUTHENTICATION_SUPPORT_H
#define POINTER_AUTHENTICATION_SUPPORT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Whether this binary was compiled for an ABI that signs pointers.
///
/// `false` on arm64 and x86_64, `true` on arm64e. When this returns `false`
/// the other two functions are guaranteed to behave as the identity.
bool pointerAuthenticationIsEnabled(void);

/// Removes the authentication bits from a code pointer signed with the
/// instruction key (`IA`), yielding the plain address.
///
/// Passing an already-unsigned pointer returns it unchanged.
uintptr_t pointerAuthenticationStripCodePointer(uintptr_t possiblySignedPointer);

/// Signs a plain code address the way a Mach-O `__auth_got` slot located at
/// `slotAddress` expects it: instruction key (`IA`), address diversity, no
/// extra discriminator.
///
/// This is the schema the linker emits for authenticated global-offset-table
/// entries holding function pointers. Callers are expected to confirm the
/// schema before trusting the result — see
/// `pointerAuthenticationStripCodePointer` round-tripping in the Swift caller.
uintptr_t pointerAuthenticationSignCodePointerForSlot(uintptr_t plainPointer, uintptr_t slotAddress);

#ifdef __cplusplus
}
#endif

#endif /* POINTER_AUTHENTICATION_SUPPORT_H */
