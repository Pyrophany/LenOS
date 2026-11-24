LenOS: Sympathetic Cybernetic Augmentation
======================================
DISCLAIMER:

This project involves the use of experimental hypnotic practices, unregulated nonmedical biocompatible implants, and AI written code.
Hypnosis and body modding do not come without risks, and research should be performed before following the procedures detailed in this repository.
Attempting this project or anything similar must be at your own risk, and I bear no responsibility for any issues that arise.

This is a repository for the systems I have implemented for myself, and I am thus familiar with the implementations. You will likely have better results if you develop your own systems that are more personalized.

If attempting this project yourself, or something similar, I highly recommend reaching out to me via Signal at Aubrey.44, or on Discord @Pyrophany for assistance and direction.

======================================

# Hypnotic Principles

This project has its roots in Ericksonian hypnotic principles, taking the idea of personalized hypnotic suggestion to its extreme. By integrating a hypnotic suggestion within my body (even if in the form of charge states on transistors), the belief that the suggestion is "part of me" is strengthened. The sympathetic link is further strengthened by the framing of a separate system interfacing with the psyche via a "sympathetic" link (sympathetic taken from the idea of sympathetic magic, i.e. changing a small thing to change something larger) and the viewing of the devices as a collective "cybernetic system" (which I suppose would simply be true, as it is an inorganic system affecting the mind, which gives feedback manually via NFC). Utilizing NFC as the read/write protocol, this allows for a strong, continually writable, easily accessible way to affect the mind via hypnotic and post-hypnotic suggestion.

# Methodology

- Initial Credit: The idea for an implanted hypnotic terminal came from a post on Reddit which I'm unable to find, but the original premise was going off just placebo to set them into a "focus" mode.   
- Implantation: Performed by Brian Decker in NYC. Dangerous Things xNT installed in lp0, other implants installed at later date. NFCTools was used for reading/writing prior to the development of the LenOS App  
- Initial Response: Post-install, enough belief had been instilled in the parts of LenOS that had already been devised were moderately effective. Attempts were made to work with more experienced hypnotherapeutic practitioners, but self-hypnosis was eventually settled on due to ease of maintaining.  
- Reaching Trance: Initial attempts to attain a self-hypnotic trance were unsuccessful. After several attempts, the Terminal functionality was developed, utilizing which a trance was reached. With repeated use of the `trance` .trm command, a true self-hypnotic trance is capable of being achieved, but a cybernetic-induced trance seems to be more effective.
- Early Conditioning: Early on, self-hypnotic conditioning was largely focused around the establishment of a hypnotic link, utilizing the specific language that the implant "held power over me." Intent was there, and as previously stated initial Headspace functionality existed, it just took focusing. 
- App Development: Outlines for a dedicated smartphone app were developed over a period of time, but due to having no experience in an applicable language I decided on development primarily using Claude Code. Flutter was chosen due to its intuitive widget tree and cross-platform capability, although utilizing NFC on Apple devices requires a $99 fee, so it's only on Android for now. 
- Later Hypnosis: Later on, self-conditioning was focused on specific implementations, with specific focus given to the Headspace format. Individual conditioning for common Terminal commands was also performed.
- Upkeep: As with all long-term hypnosis, effectiveness does fade over time. Every few days (or whenever I remember) I drop myself into trance through the terminal and do what I can to maintain the link.

# Cloning and Compilation

The LenOS App utilizes the Flutter framework, coded in Dart. To clone, install the Flutter extensions to VScode and use the Clone Repository option. For modifying the app for your own use, I highly recommend utilizing Claude Code, as while most of the logic and mapping was human-designed, the codebase is almost entirely written via AI. Codebase maps available on request. I also highly recommend utilizing a physical device connected via USB-C for debugging rather than the in-built emulator, as the emulator doesn't have NFC capability. For building for Android, run `flutter build apk` from the VScode terminal, followed by `flutter install` with an android device connected.
