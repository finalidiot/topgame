package org.spinningmetal.qa003a;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** Real Android touchscreen injection restricted to Spinning Metal's activity.
 * No accessibility service, arbitrary device UI, screenshot/collection edits,
 * game-state grants, network calls or shell execution live in this test APK.
 */
public final class TouchDriver extends Instrumentation {
    private static final String TARGET = "org.spinningmetal.prototype";
    private Bundle arguments;
    private Activity activity;
    private final LinkedHashMap<Integer, float[]> pointers = new LinkedHashMap<>();
    private JSONArray ledger = new JSONArray();
    private final float[] viewport = new float[4];
    private long downTime;
    private int eventCount;

    @Override public void onCreate(Bundle args) {
        arguments = args;
        super.onCreate(args);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            if (!TARGET.equals(getTargetContext().getPackageName()))
                throw new IllegalStateException("Instrumentation target is not Spinning Metal");
            Intent launch = getTargetContext().getPackageManager().getLaunchIntentForPackage(TARGET);
            if (launch == null || launch.getComponent() == null || !TARGET.equals(launch.getComponent().getPackageName()))
                throw new IllegalStateException("Known game launcher was not found");
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            activity = startActivitySync(launch);
            waitForIdleSync();
            SystemClock.sleep(Math.max(0, Math.min(3000, arguments.getInt("settle_ms", 250))));
            requireGameFocus();
            final int[] size = new int[2];
            runOnMainSync(() -> {
                size[0] = activity.getWindow().getDecorView().getWidth();
                size[1] = activity.getWindow().getDecorView().getHeight();
            });
            String session = arguments.getString("session", "");
            if (!session.isEmpty()) {
                queue(session, size);
                result.putBoolean("passed", true);
                result.putString("session", session);
                result.putString("activity", activity.getClass().getName());
                result.putInt("event_count", eventCount);
                finish(Activity.RESULT_OK, result);
                return;
            }
            JSONObject script = new JSONObject(arguments.getString("script", "{}"));
            configureViewport(script.getJSONArray("viewport"), size);
            JSONArray steps = script.getJSONArray("steps");
            validateSteps(steps);
            for (int i = 0; i < steps.length(); i++) execute(steps.getJSONObject(i), i);
            if (!pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL);
            result.putBoolean("passed", true);
            result.putString("activity", activity.getClass().getName());
            result.putInt("screen_width", size[0]);
            result.putInt("screen_height", size[1]);
            result.putInt("event_count", eventCount);
            result.putString("ledger", ledger.toString());
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            // Never inject cleanup into another foreground application.
            try { if (activity != null && focused() && !pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL); }
            catch (Throwable ignored) { }
            result.putBoolean("passed", false);
            result.putString("error", error.getClass().getSimpleName() + ": " + error.getMessage());
            result.putInt("event_count", eventCount);
            result.putString("ledger", ledger.toString());
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private void configureViewport(JSONArray rectangle, int[] size) throws Exception {
        if (rectangle.length() != 4) throw new IllegalArgumentException("viewport must contain left,top,width,height");
        for (int i = 0; i < 4; i++) viewport[i] = (float) rectangle.getDouble(i);
        for (float value : viewport) if (!Float.isFinite(value)) throw new IllegalArgumentException("Viewport must be finite");
        if (viewport[0] < 0 || viewport[1] < 0 || viewport[2] <= 0 || viewport[3] <= 0 || viewport[2] > 8192 || viewport[3] > 8192)
            throw new IllegalArgumentException("Invalid letterboxed gameplay viewport");
        if (viewport[0] + viewport[2] > size[0] + 2 || viewport[1] + viewport[3] > size[1] + 2)
            throw new IllegalArgumentException("Viewport extends beyond this game window");
    }

    private void validateSteps(JSONArray steps) throws Exception {
        if (steps.length() == 0 || steps.length() > 240) throw new IllegalArgumentException("Bounded 1-240 touch steps required");
        long requestedTime = 0;
        for (int i = 0; i < steps.length(); i++) {
            JSONObject step = steps.getJSONObject(i);
            int ms = step.optInt("ms", 0);
            if (ms < 0 || ms > 20000) throw new IllegalArgumentException("Each step lasts at most twenty seconds");
            requestedTime += ms;
            String type = step.getString("type");
            if (!type.equals("down") && !type.equals("move") && !type.equals("up") && !type.equals("cancel") && !type.equals("wait"))
                throw new IllegalArgumentException("Only fixed touchscreen steps are permitted");
        }
        if (requestedTime > 120000) throw new IllegalArgumentException("A single script lasts at most two minutes");
    }

    private String read(File file) throws Exception {
        long size = file.length();
        if (size <= 0 || size > 131072) throw new IllegalArgumentException("Bounded JSON input required");
        byte[] bytes = new byte[(int) size];
        try (FileInputStream stream = new FileInputStream(file)) {
            int read = 0;
            while (read < bytes.length) {
                int count = stream.read(bytes, read, bytes.length - read);
                if (count < 0) throw new IllegalArgumentException("Incomplete JSON input");
                read += count;
            }
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    private void write(File destination, JSONObject value) throws Exception {
        File temporary = new File(destination.getParentFile(), destination.getName() + ".tmp");
        try (FileOutputStream stream = new FileOutputStream(temporary)) {
            stream.write(value.toString().getBytes(StandardCharsets.UTF_8));
            stream.getFD().sync();
        }
        if (!temporary.renameTo(destination)) throw new IllegalStateException("Could not atomically save test receipt");
    }

    private void queue(String session, int[] size) throws Exception {
        if (!session.matches("[0-9a-f]{32}")) throw new IllegalArgumentException("Session must be thirty-two lowercase hexadecimal characters");
        File files = getTargetContext().getFilesDir().getCanonicalFile();
        File marker = new File(files, "qa003a/request.json");
        if (!marker.isFile() || !session.equals(new JSONObject(read(marker)).optString("run_id")))
            throw new IllegalArgumentException("Session does not match the game's explicit isolated QA marker");
        File directory = new File(files, "qa003a/" + session).getCanonicalFile();
        if (!directory.getPath().startsWith(new File(files, "qa003a").getCanonicalPath() + File.separator))
            throw new IllegalArgumentException("Session path escaped its game-only QA directory");
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("Could not create scoped queue directory");
        JSONObject ready = new JSONObject();
        ready.put("passed", true); ready.put("session", session); ready.put("target", TARGET);
        ready.put("activity", activity.getClass().getName()); ready.put("screen_width", size[0]); ready.put("screen_height", size[1]);
        ready.put("max_seconds", 900); ready.put("max_steps_per_command", 240);
        write(new File(directory, "touch_ready.json"), ready);
        File command = new File(directory, "touch_command.json");
        long deadline = SystemClock.uptimeMillis() + 900000;
        int lastSequence = -1;
        int totalSteps = 0;
        while (SystemClock.uptimeMillis() < deadline) {
            if (!command.isFile()) { SystemClock.sleep(40); continue; }
            JSONObject request = new JSONObject(read(command));
            int sequence = request.getInt("sequence");
            if (sequence < 0 || sequence > 100000) throw new IllegalArgumentException("Sequence is outside the bounded range");
            if (sequence <= lastSequence) { SystemClock.sleep(40); continue; }
            lastSequence = sequence;
            ledger = new JSONArray();
            JSONObject receipt = new JSONObject();
            receipt.put("sequence", sequence); receipt.put("session", session);
            boolean finished = request.optBoolean("finish", false);
            try {
                if (finished) {
                    if (focused() && !pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL);
                } else {
                    configureViewport(request.getJSONArray("viewport"), size);
                    JSONArray steps = request.getJSONArray("steps");
                    validateSteps(steps);
                    totalSteps += steps.length();
                    if (totalSteps > 5000) throw new IllegalArgumentException("Session step cap exceeded");
                    for (int i = 0; i < steps.length(); i++) {
                        if (SystemClock.uptimeMillis() >= deadline) throw new IllegalStateException("Session time limit reached");
                        execute(steps.getJSONObject(i), i);
                    }
                }
                receipt.put("passed", true);
            } catch (Throwable error) {
                if (focused() && !pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL);
                receipt.put("passed", false);
                receipt.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
            }
            receipt.put("ledger", ledger); receipt.put("event_count", eventCount); receipt.put("active_pointers", pointers.size());
            receipt.put("uptime_ms", SystemClock.uptimeMillis());
            write(new File(directory, "touch_receipt_" + sequence + ".json"), receipt);
            write(new File(directory, "touch_receipt.json"), receipt);
            if (finished) return;
        }
        if (focused() && !pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL);
        JSONObject expired = new JSONObject(); expired.put("passed", false); expired.put("session", session); expired.put("reason", "Fifteen minute queue deadline");
        write(new File(directory, "touch_expired.json"), expired);
        throw new IllegalStateException("Fifteen minute queue deadline");
    }

    private boolean focused() {
        final boolean[] hasFocus = {false};
        runOnMainSync(() -> hasFocus[0] = activity != null && !activity.isFinishing() && activity.hasWindowFocus()
                && TARGET.equals(activity.getPackageName()));
        return hasFocus[0];
    }
    private void requireGameFocus() {
        if (!focused()) throw new IllegalStateException("Only the foreground Spinning Metal activity may receive touch input");
    }
    private float[] point(JSONArray value) throws Exception {
        if (value.length() != 2) throw new IllegalArgumentException("Native point needs x,y");
        float x = (float) value.getDouble(0), y = (float) value.getDouble(1);
        if (!Float.isFinite(x) || !Float.isFinite(y) || x < 0 || x > 640 || y < 0 || y > 360)
            throw new IllegalArgumentException("Point is outside the native640x360 game image");
        return new float[]{x, y};
    }
    private int pointerId(JSONObject step) throws Exception {
        int id = step.getInt("id");
        if (id < 0 || id > 4) throw new IllegalArgumentException("Pointer IDs are bounded to0-4");
        return id;
    }
    private int indexOf(int id) {
        int index = 0;
        for (int key : pointers.keySet()) { if (key == id) return index; index++; }
        throw new IllegalArgumentException("Pointer does not own a contact");
    }
    private void execute(JSONObject step, int number) throws Exception {
        requireGameFocus();
        String type = step.getString("type");
        if (type.equals("wait")) {
            SystemClock.sleep(step.optInt("ms", 0));
        } else if (type.equals("down")) {
            int id = pointerId(step);
            if (pointers.containsKey(id) || pointers.size() >= 5) throw new IllegalArgumentException("Pointer already down or contact cap exceeded");
            if (pointers.isEmpty()) downTime = SystemClock.uptimeMillis();
            pointers.put(id, point(step.getJSONArray("point")));
            send(pointers.size() == 1 ? MotionEvent.ACTION_DOWN : MotionEvent.ACTION_POINTER_DOWN | (indexOf(id) << MotionEvent.ACTION_POINTER_INDEX_SHIFT));
            SystemClock.sleep(step.optInt("ms", 0));
        } else if (type.equals("move")) {
            if (pointers.isEmpty()) throw new IllegalArgumentException("Move needs an owned contact");
            JSONArray moves = step.getJSONArray("pointers");
            LinkedHashMap<Integer, float[]> origins = new LinkedHashMap<>();
            LinkedHashMap<Integer, float[]> destinations = new LinkedHashMap<>();
            for (int i = 0; i < moves.length(); i++) {
                JSONObject move = moves.getJSONObject(i);
                int id = pointerId(move);
                if (!pointers.containsKey(id) || destinations.containsKey(id)) throw new IllegalArgumentException("Move pointer is absent or duplicated");
                origins.put(id, pointers.get(id).clone());
                destinations.put(id, point(move.getJSONArray("point")));
            }
            int ms = step.optInt("ms", 0);
            int samples = Math.max(1, Math.min(600, step.optInt("samples", Math.max(1, ms / 16))));
            long began = SystemClock.uptimeMillis();
            for (int sample = 1; sample <= samples; sample++) {
                float progress = (float) sample / samples;
                for (int id : destinations.keySet()) {
                    float[] a = origins.get(id), b = destinations.get(id);
                    pointers.put(id, new float[]{a[0] + (b[0] - a[0]) * progress, a[1] + (b[1] - a[1]) * progress});
                }
                send(MotionEvent.ACTION_MOVE);
                long sleep = began + Math.round(ms * progress) - SystemClock.uptimeMillis();
                if (sleep > 0) SystemClock.sleep(sleep);
            }
        } else if (type.equals("up")) {
            int id = pointerId(step);
            int index = indexOf(id);
            send(pointers.size() == 1 ? MotionEvent.ACTION_UP : MotionEvent.ACTION_POINTER_UP | (index << MotionEvent.ACTION_POINTER_INDEX_SHIFT));
            pointers.remove(id);
            SystemClock.sleep(step.optInt("ms", 0));
        } else if (type.equals("cancel")) {
            if (!pointers.isEmpty()) send(MotionEvent.ACTION_CANCEL);
            pointers.clear();
        } else throw new IllegalArgumentException("Only down/move/up/cancel/wait steps are supported");
        JSONObject item = new JSONObject();
        item.put("step", number); item.put("type", type); item.put("uptime_ms", SystemClock.uptimeMillis());
        item.put("active_pointers", pointers.size());
        ledger.put(item);
    }
    private void send(int action) throws Exception {
        requireGameFocus();
        int count = pointers.size();
        if (count == 0) throw new IllegalArgumentException("No contacts to send");
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[count];
        MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[count];
        int index = 0;
        for (Map.Entry<Integer, float[]> entry : pointers.entrySet()) {
            MotionEvent.PointerProperties property = new MotionEvent.PointerProperties();
            property.id = entry.getKey(); property.toolType = MotionEvent.TOOL_TYPE_FINGER;
            MotionEvent.PointerCoords coordinate = new MotionEvent.PointerCoords();
            coordinate.x = viewport[0] + entry.getValue()[0] / 640.0f * viewport[2];
            coordinate.y = viewport[1] + entry.getValue()[1] / 360.0f * viewport[3];
            coordinate.pressure = 1; coordinate.size = 0.02f;
            properties[index] = property; coordinates[index] = coordinate; index++;
        }
        MotionEvent event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, count, properties,
                coordinates, 0, 0, 1, 1, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        try { sendPointerSync(event); eventCount++; }
        finally { event.recycle(); }
        if (action == MotionEvent.ACTION_CANCEL) pointers.clear();
    }
}
