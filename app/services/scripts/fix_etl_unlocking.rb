module Scripts
  class FixETLUnlocking
    include Mandate

    def call
      Track.all.each do |track|
        fix_track(track)
      end
    end

    # Note: This doesn't take into consideration exercises
    # completed without approval. That should be added before
    # this is run in the future.
    def fix_track(track)
      core_exercises = track.exercises.core.order("position ASC")
      core_exercise_ids = core_exercises.map(&:id)
      side_exercises = track.exercises.side
      unlocked_by, auto_unlock = side_exercises.partition { |e| e.unlocked_by_id.present? }

      UserTrack.includes(:user).where(track_id: track.id).each do |ut|
        user = ut.user

        # Get core exercises for checking
        existing_core_ids = Solution.joins(:exercise).where('exercises.core': true).where(user_id: ut.user_id, "exercises.track_id": ut.track_id).pluck(:exercise_id)

        # Unlock the first core if appropriate
        # Do this before getting the other stuff
        if (core_exercise_ids & existing_core_ids).empty?
          CreatesSolution.create!(user, core_exercises.first)
        end

        # Get side exercises for checking
        existing_completed_exercise_ids = Solution.joins(:exercise).where(user_id: ut.user_id, "exercises.track_id": ut.track_id).completed.pluck(:exercise_id)
        existing_uncompleted_exercise_ids = Solution.joins(:exercise).where(user_id: ut.user_id, "exercises.track_id": ut.track_id).not_completed.pluck(:exercise_id)
        existing_exercise_ids = existing_completed_exercise_ids + existing_uncompleted_exercise_ids

        # Unlock the first core if appropriate
        if (core_exercise_ids & existing_exercise_ids).empty?
          CreatesSolution.create!(user, core_exercises.first)
        end

        # Unlock auto unlocks
        auto_unlock.each do |side_exercise|
          unless existing_exercise_ids.include?(side_exercise.id)
            CreatesSolution.create!(user, side_exercise)
          end
        end

        # Unlock unlocked side exercsies
        unlocked_by.each do |side_exercise|
          if !existing_exercise_ids.include?(side_exercise.id) &&
             existing_completed_exercise_ids.include?(side_exercise.unlocked_by_id)
            CreatesSolution.create!(user, side_exercise)
          end
        end
      end
    end
  end
end
