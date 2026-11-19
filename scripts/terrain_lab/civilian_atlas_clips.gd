extends RefCounted
## Phase one: rates and sample counts match the original GPU baker. Phase two (CIV-A3): the four civilian work clips,
## built at capture time by civilian_work_clips.gd. ALL is the recipe order: the work clips follow "down" (a one-shot,
## so the editor's loop toggle is off for them and their last sample is the true last pose, never a wrap to frame 0).
const CLIPS := [
 {"id":"idle","samples":4,"rate":12}, {"id":"walk","samples":8,"rate":24},
 {"id":"run","samples":8,"rate":30}, {"id":"hit","samples":8,"rate":24},
 {"id":"knockback","samples":8,"rate":24}, {"id":"down","samples":12,"rate":24},
 {"id":"unconscious","samples":4,"rate":24}, {"id":"get_up","samples":12,"rate":24}]
const WORK := [
 {"id":"civilian_carry","samples":8,"rate":24}, {"id":"civilian_lift","samples":12,"rate":24},
 {"id":"civilian_sit","samples":8,"rate":24}, {"id":"civilian_fetch_water","samples":12,"rate":24}]
const ALL := [
 {"id":"idle","samples":4,"rate":12}, {"id":"walk","samples":8,"rate":24},
 {"id":"run","samples":8,"rate":30}, {"id":"hit","samples":8,"rate":24},
 {"id":"knockback","samples":8,"rate":24}, {"id":"down","samples":12,"rate":24},
 {"id":"civilian_carry","samples":8,"rate":24}, {"id":"civilian_lift","samples":12,"rate":24},
 {"id":"civilian_sit","samples":8,"rate":24}, {"id":"civilian_fetch_water","samples":12,"rate":24},
 {"id":"unconscious","samples":4,"rate":24}, {"id":"get_up","samples":12,"rate":24}]
const DIRECTIONS := [{"id":"down","yaw":0.0},{"id":"left","yaw":-90.0},{"id":"up","yaw":180.0},{"id":"right","yaw":90.0}]
