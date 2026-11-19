extends RefCounted
## Phase one only. Rates and sample counts match the original GPU baker.
const CLIPS := [
 {"id":"idle","samples":4,"rate":12}, {"id":"walk","samples":8,"rate":24},
 {"id":"run","samples":8,"rate":30}, {"id":"hit","samples":8,"rate":24},
 {"id":"knockback","samples":8,"rate":24}, {"id":"down","samples":12,"rate":24},
 {"id":"unconscious","samples":4,"rate":24}, {"id":"get_up","samples":12,"rate":24}]
const DIRECTIONS := [{"id":"down","yaw":0.0},{"id":"left","yaw":-90.0},{"id":"up","yaw":180.0},{"id":"right","yaw":90.0}]
