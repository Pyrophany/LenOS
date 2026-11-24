# LenOS: Sympathetic Cybernetic Augmentation
DISCLAIMER:

This project involves the use of experimental hypnotic practices, unregulated nonmedical biocompatible implants, and AI written code.
Hypnosis and body modding do not come without risks, and research should be performed before following the procedures detailed in this repository.
Attempting this project or anything similar must be at your own risk, and I bear no responsibility for any issues that arise.

This is a repository for the systems I have implemented for myself, and I am thus familiar with the implementations. You will likely have better results if you develop your own systems that are more personalized.

If attempting this project yourself, or something similar, I highly recommend reaching out to me via Signal at Aubrey.44, or on Discord @Pyrophany for assistance and direction.


### Hypnotic Principles
This project has its roots in Ericksonian hypnotic principles, taking the idea of personalized hypnotic suggestion to its extreme. By integrating a hypnotic suggestion within my body (even if in the form of charge states on transistors), the belief that the suggestion is "part of me" is strengthened. The sympathetic link is further strengthened by the framing of a separate system interfacing with the psyche via a "sympathetic" link (sympathetic taken from the idea of sympathetic magic, i.e. changing a small thing to change something larger) and the viewing of the devices as a collective "cybernetic system" (which I suppose would simply be true, as it is an inorganic system affecting the mind, which gives feedback manually via NFC). Utilizing NFC as the read/write protocol, this allows for a strong, continually writable, easily accessible way to affect the mind via hypnotic and post-hypnotic suggestion.

### Methodology
* Initial Credit: The idea for an implanted hypnotic terminal came from a post on Reddit which I'm unable to find, but the original premise was going off just placebo to set them into a "focus" mode.   
* Implantation: Performed by Brian Decker in NYC. Dangerous Things xNT installed in lp0, other implants installed at later date. NFCTools was used for reading/writing prior to the development of the LenOS App  
* Initial Response: Post-install, enough belief had been instilled in the parts of LenOS that had already been devised were moderately effective. Attempts were made to work with more experienced hypnotherapeutic practitioners, but self-hypnosis was eventually settled on due to ease of maintaining.  
* Reaching Trance: Initial attempts to attain a self-hypnotic trance were unsuccessful. After several attempts, the Terminal functionality was developed, utilizing which a trance was reached. With repeated use of the `trance` .trm command, a true self-hypnotic trance is capable of being achieved, but a cybernetic-induced trance seems to be more effective.
* Early Conditioning: Early on, self-hypnotic conditioning was largely focused around the establishment of a hypnotic link, utilizing the specific language that the implant "held power over me." Intent was there, and as previously stated initial Headspace functionality existed, it just took focusing. 
* App Development: Outlines for a dedicated smartphone app were developed over a period of time, but due to having no experience in an applicable language I decided on development primarily using Claude Code. Flutter was chosen due to its intuitive widget tree and cross-platform capability, although utilizing NFC on Apple devices requires a $99 fee, so it's only on Android for now. 
* Later Hypnosis: Later on, self-conditioning was focused on specific implementations, with specific focus given to the Headspace format. Individual conditioning for common Terminal commands was also performed.
* Upkeep: As with all long-term hypnosis, effectiveness does fade over time. Every few days (or whenever I remember) I drop myself into trance through the terminal and do what I can to maintain the link.

### Cloning and Compilation
The LenOS App utilizes the Flutter framework, coded in Dart. To clone, install the Flutter extensions to VScode and use the Clone Repository option. For modifying the app for your own use, I highly recommend utilizing Claude Code, as while most of the logic and mapping was human-designed, the codebase is almost entirely written via AI. Codebase maps available on request. I also highly recommend utilizing a physical device connected via USB-C for debugging rather than the in-built emulator, as the emulator doesn't have NFC capability. For building for Android, run `flutter build apk` from the VScode terminal, followed by `flutter install` with an android device connected.

# System Documentation

**LenOS is an object-oriented system, intended for emotional regulation, personal improvement, and recreation. The primary component, the LenOS Cybernetic System (LCS) consists of multiple DT xNT biocompatible NFC chips, communicable via 13.56MHz ISO14443A and NFC Type 2, physically separate from the endocrine and nervous systems but interfacing with the psyche through a sympathetic link induced via hypnotic conditioning.**

***

**Chips are split into three banks:**   
- INTERFACE- one chip located at LP0, intended for short-term augmentation and the running of Terminal commands.  
- SYSTEM- one chip located at RP0, used for long-term modification and eventual integration of behavioral modifications into the overall psyche.  
- MEMORY- multiple chips located in the left forearm, utilized for storage of links, important information, and text registers. Not currently implemented.  

***

**LenOS utilizes two filetypes to affect the mind:**  
- .trm files are temporary commands from the terminal, cleared upon each next write. Largely implemented as embedded triggers, but most commands will have an effect if understood. .trm files follow the following format: `USER@LenOS:~$ [COMMAND] [ARGUMENTS]`  
Hardcoded terminal command `fractionate` sends and deletes `USER@LenOS:~$ trance` in intervals.
- .len files are the primary vector for emotional, behavioral, and headspace changes. Implemented in a more generalized form, with individual conditioning used as necessary. All .len files follow the following format: all necessary mixins, a type import, and the wrapper, which begins with a name identifier.  
Example file:
```
mixin LenOS-DEVICE
import.LenOS:Example
{
nameIdentifier:example
BODY
}
```


***

## **There are three types of .len files**

**Program** files are utilized by the SYSTEM implant for long-term modification and improvement, and over a period of approximately three months are integrated into the overall psyche. Program files can utilize two specialized mixins: `LenOS-CONSCIOUS` and `LenOS-UNCONSCIOUS` to affect the conscious and unconscious mind's decision making respectively.  
Example:
```
mixin LenOS-SYSTEM
mixin LenOS-[mind]
import.LenOS:Program
{
ProgramName:[NAME]
BODY
}
```

**Package** files are used by the INTERFACE implant for more extreme short-term modifications, such as forcing completion of a specified task, playing a character, or implementing temporary restrictions.  
Example:
```
mixin LenOS-INTERFACE
import.LenOS:Package
{
PackageName:[NAME]
BODY
}
```


**Headspace** files modify the current headspace/emotional state and follow a strict format. They are exclusively used on the INTERFACE device, and are always the first file in the registry. Files can be inputted either manually or via the Headspace Manager.\
Example:
```
mixin LenOS-INTERFACE
import.LenOS:Headspace
{
Headspace:[EXAMPLE]
Traits:[trait1],[trait2],[trait3]
Modifier:(modifier)
}
```

***

## **File BODY format**

LenOS Files are further encapsulated by splitting up individual parts of a program or package into subroutines called Functions. For example, a program intended to restrict phone use may have two functions in it, one that redirects focus away from the phone when picking it up absentmindedly and one that redirects focus away from the phone when a necessary task is completed on it. Functions, once defined in a loaded Program, can be called anywhere without re-defining. Functions follow the following format: `function FunctionName{}`

**Functions are then coded via a simplistic object-oriented logic system, written around `LOGIC`, `event_handlers`, and `actionWords`.**  

Logic variables are simple standalone modifiers to the code around them. They are always capitalized. Examples: `IS, ON, NOT, WHEN, IF, NOT, OR`  

Event Handlers listen for events before continuing in their function routine, usually occurring preceded by a logic variable such as WHEN or ON. If the event is tied to a specific object, that object is separated by a `:` colon. Example: `ON pickup:Phone`

Action Words are tasks or actions already defined within the psyche. Tasks are further specified after in a set of `()` parentheses, and even further within via a `:` colon. Example: `focusRedirect(on_task)`

**Adding all that up, we get:**
```
function ModifyDopmLoop{
 ON pickup:phone
 FocusRedirect(on_task)
}
```
### Complete Example File:

```
mixin LenOS-SYSTEM
mixin LenOS-Conscious
mixin LenOS-Unconscious
import.LenOS: Program
{
PackageName: PhoneUseRestriction
function ModifyDopmLoop{
 ON pickup:phone
 focusRedirect(on_task) OR putDown(phone)
 }
function PreventDistraction{
 WHILE using:phone
 ON task_complete
 setFocus NOT (phone)
 }
}
```

