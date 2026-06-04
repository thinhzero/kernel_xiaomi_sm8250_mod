#include <linux/types.h>
#include <linux/cache.h>

bool ksu_vfs_read_hook __read_mostly = false;
bool ksu_execveat_hook __read_mostly = false;
bool ksu_input_hook __read_mostly = false;
bool susfs_is_boot_completed_triggered __read_mostly = false;
