/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

oneway interface IProgressCallback {
    void onProgress(int percent, @utf8InCpp String text);
    void onLog(@utf8InCpp String line);
    /** From here on, cancel() is refused: stopping would break the target */
    void onDestructive();
    /** error is empty on success */
    void onFinished(boolean success, @utf8InCpp String error);
}
