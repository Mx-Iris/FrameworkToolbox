#include "PointerAuthenticationSupport.h"

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

bool pointerAuthenticationIsEnabled(void) {
#if __has_feature(ptrauth_calls)
    return true;
#else
    return false;
#endif
}

uintptr_t pointerAuthenticationStripCodePointer(uintptr_t possiblySignedPointer) {
#if __has_feature(ptrauth_calls)
    if (possiblySignedPointer == 0) {
        return 0;
    }
    return (uintptr_t)ptrauth_strip((void *)possiblySignedPointer, ptrauth_key_asia);
#else
    return possiblySignedPointer;
#endif
}

uintptr_t pointerAuthenticationSignCodePointerForSlot(uintptr_t plainPointer, uintptr_t slotAddress) {
#if __has_feature(ptrauth_calls)
    if (plainPointer == 0) {
        return 0;
    }
    return (uintptr_t)ptrauth_sign_unauthenticated((void *)plainPointer, ptrauth_key_asia, slotAddress);
#else
    (void)slotAddress;
    return plainPointer;
#endif
}
