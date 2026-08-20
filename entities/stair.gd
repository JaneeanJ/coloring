extends Node


func create_stairs():

	for i in range(20):

		var step = StaticBody3D.new()

		step.name = "Step_" + str(i)


		# 台阶模型
		var mesh = MeshInstance3D.new()

		var box = BoxMesh.new()

		box.size = Vector3(3,0.2,2)

		mesh.mesh = box

		step.add_child(mesh)



		# 碰撞
		var collision = CollisionShape3D.new()

		var shape = BoxShape3D.new()

		shape.size = Vector3(3,0.2,2)

		collision.shape = shape

		step.add_child(collision)



		# 每一级升高
		step.position = Vector3(
			3,
			i * 0.3,
			-i * 1.5
		)


		add_child(step)
