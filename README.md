LibResInfo-1.0
=================

LibResInfo detects resurrection spell casts and identifies who they are being cast on, and provides that information to addons through callbacks and API methods. It also supports Mass Resurrection and Soulstone. It is fully embeddable, completely locale-independent, and does not require any other players in your group to have anything installed.

Requires [LibStub](http://www.wowace.com/addons/libstub/) and [CallbackHandler-1.0](http://www.wowace.com/addons/callbackhandler/).

* [Download on CurseForge](http://wow.curseforge.com/addons/libresinfo/)
* [Download on WoWInterface](http://www.wowinterface.com/downloads/info21467-LibResInfo-1.0.html)


## API Documentation:

* [API methods](https://github.com/Phanx/LibResInfo/wiki/API-Methods)
* [Callbacks](https://github.com/Phanx/LibResInfo/wiki/Callbacks)


## Embedding

If you are the CurseForge/WowAce packager, you should use the following URL in your .pkgmeta file:

    svn://svn.wowinterface.com/LibResInfo-976/trunk/LibResInfo-1.0

If you use a Git URL instead, you will get a number of irrelevant documentation and metadata files, and an extra layer of folders, since Git does not support checking out only part of the repository, and the Curse packager does not support checking out from GitHub over SVN. You're welcome to add `libresinfo` to the `tools-used` section of your .pkgmeta file so I get Curse points for the library usage, but it's not required.


## Additional Notes

Support for Reincarnation is under consideration, but would require some guesswork, since until you actually see a shaman resurrect themselves, there's no way to tell if the ability is on cooldown or not.

No callbacks are fired for players who die while Mass Resurrection is being cast, but the API will return correct information (that the player has an incoming resurrection) so if it important for your addon, just check the player's status when they die.

No callbacks are fired for players who resurrect themselves by returning to their corpse while Mass Resurrection is the only res casting on them, but the API will (again) return correct information (that the player has no incoming resurrection) so if it important for your addon, just check the player's status when they resurrect.


## Limitations

Due to limitations of the WoW API, it is **not possible** to detect:

* ...when someone declines a resurrection manually by clicking "Decline" on the dialog box.
* ...when someone has a wait time before they can accept a resurrection. In this case, the 60-second expiration time will be extended by the amount of time they are forced to wait, but the ResExpired callback will be fired at the 60-second mark since there's no way for LRI to know about the wait time.
* ...who a player who joins the group while casting a resurrection spell is targeting.
* ...whether a player who joins the group while dead has a resurrection being cast on them.
* ...whether a player who joins the group while dead has a resurrection already available.
