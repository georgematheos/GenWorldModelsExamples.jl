using Gen
using GenDirectionalStats
using PoseComposition: Pose

start_poses = [
    T.uniformPose(-20.0, 20.0, -20.0,20.0,50.0,100.0),
    T.uniformPose(-20.0, 20.0, -20.0,20.0,50.0,100.0)
]
new_poses = []
poses = start_poses
for t=1:50
    push!(new_poses, [
        Pose(
            Gen.mvnormal(start_pose.pos, [1. 0 0; 0 1 0; 0 0 1]),
            GenDirectionalStats.vmf_rot3(start_pose.orientation, 100)
        ) for start_pose in poses
    ])
end

ids = [2, 5]
frames = [
    [(ids[i], pose.pos, pose.orientation) for (i, pose) in enumerate(poses)]
    for poses in append!([start_poses], new_poses)
]