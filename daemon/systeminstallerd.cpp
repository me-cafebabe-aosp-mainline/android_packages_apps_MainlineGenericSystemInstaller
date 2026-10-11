/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

// Runs /system_ext/bin/systeminstaller for SystemInstaller, and turns its
// output (see scripts/lib/common.sh) into AIDL results and callbacks.

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <aidl/device/mainline/generic/installer/BnSystemInstaller.h>
#include <android-base/logging.h>
#include <android-base/parseint.h>
#include <android-base/strings.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>
#include <private/android_filesystem_config.h>

namespace installer = aidl::device::mainline::generic::installer;

using android::base::ParseInt;
using android::base::Split;
using ndk::ScopedAStatus;

namespace {

constexpr char kServiceName[] = "device.mainline.generic.installer.ISystemInstaller/default";
constexpr char kScript[] = "/system_ext/bin/systeminstaller";
// The output of the last installation. The scripts copy it to the target
// (SI_LOG).
constexpr char kLog[] = "/data/system/systeminstaller.log";

ScopedAStatus IllegalState(const char* message) {
    return ScopedAStatus::fromExceptionCodeWithMessage(EX_ILLEGAL_STATE, message);
}

bool CallerAllowed() {
    uid_t uid = AIBinder_getCallingUid();
    return uid == AID_SYSTEM || uid == AID_ROOT;
}

int64_t ToInt64(const std::string& s, int64_t fallback = 0) {
    int64_t v;
    return ParseInt(s, &v) ? v : fallback;
}

// Runs the script with the arguments, calls on_line for every line of its
// output (stdout and stderr), returns its exit status. pid_out gets the
// process ID while it runs. log, when given, is passed as SI_LOG.
int RunScript(const std::vector<std::string>& args,
              const std::function<void(const std::string&)>& on_line,
              std::atomic<pid_t>* pid_out, const char* log = nullptr) {
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        PLOG(ERROR) << "pipe2";
        return -1;
    }
    pid_t pid = fork();
    if (pid < 0) {
        PLOG(ERROR) << "fork";
        close(fds[0]);
        close(fds[1]);
        return -1;
    }
    if (pid == 0) {
        dup2(fds[1], STDOUT_FILENO);
        dup2(fds[1], STDERR_FILENO);
        if (log) setenv("SI_LOG", log, 1);
        std::vector<char*> argv;
        argv.push_back(const_cast<char*>(kScript));
        for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
        argv.push_back(nullptr);
        execv(kScript, argv.data());
        _exit(127);
    }
    close(fds[1]);
    if (pid_out) *pid_out = pid;

    FILE* out = fdopen(fds[0], "r");
    char* line = nullptr;
    size_t size = 0;
    ssize_t len;
    while ((len = getline(&line, &size, out)) >= 0) {
        std::string s(line, len);
        if (!s.empty() && s.back() == '\n') s.pop_back();
        on_line(s);
    }
    free(line);
    fclose(out);

    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    if (pid_out) *pid_out = -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

class SystemInstaller : public installer::BnSystemInstaller {
  public:
    ScopedAStatus probe(installer::ProbeResult* result) override {
        if (!CallerAllowed()) return ScopedAStatus::fromExceptionCode(EX_SECURITY);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (running_) return IllegalState("An installation is running");
        }
        std::string error;
        int status = RunScript(
                {"probe"},
                [&](const std::string& line) {
                    auto f = Split(line, "\t");
                    if (f[0] == "SYSTEM" && f.size() >= 11) {
                        auto& s = result->system;
                        s.uefi = f[1] == "uefi";
                        s.efiBits = ToInt64(f[2]);
                        s.secureBoot = f[3].empty() ? -1 : ToInt64(f[3]);
                        s.arch = f[4];
                        s.device = f[5];
                        s.buildDateUtc = ToInt64(f[6]);
                        s.title = f[7];
                        s.defaultCmdline = f[8];
                        s.sourceFound = f[9] == "1";
                        s.sourceMessage = f[10];
                    } else if (f[0] == "DISK" && f.size() >= 7) {
                        result->disks.push_back({.name = f[1],
                                                 .sizeBytes = ToInt64(f[2]),
                                                 .removable = f[3] == "1",
                                                 .usable = f[4] == "1",
                                                 .model = f[5],
                                                 .reason = f[6],
                                                 .type = f.size() >= 8 ? f[7] : ""});
                    } else if (f[0] == "PART" && f.size() >= 10) {
                        result->partitions.push_back({.name = f[1],
                                                      .disk = f[2],
                                                      .sizeBytes = ToInt64(f[3]),
                                                      .fsType = f[4],
                                                      .label = f[5],
                                                      .freeMiB = ToInt64(f[6], -1),
                                                      .usable = f[7] == "1",
                                                      .os = f[8],
                                                      .reason = f[9]});
                    } else if (f[0] == "INSTALL" && f.size() >= 6) {
                        int kind = f[2] == "disk"     ? installer::Installation::KIND_DISK
                                   : f[2] == "beside" ? installer::Installation::KIND_BESIDE
                                                      : installer::Installation::KIND_PACKAGE;
                        result->installations.push_back({.id = f[1],
                                                         .kind = kind,
                                                         .buildDateUtc = ToInt64(f[3]),
                                                         .upgradable = f[4] == "1",
                                                         .reason = f[5]});
                    } else if (f[0] == "LAYOUT" && f.size() >= 4) {
                        result->layout.push_back({.name = f[1],
                                                  .defaultMiB = static_cast<int32_t>(ToInt64(f[2])),
                                                  .minimumMiB = static_cast<int32_t>(ToInt64(f[3]))});
                    } else if (f[0] == "ERROR" && f.size() >= 2) {
                        error = f[1];
                    } else {
                        LOG(INFO) << "probe: " << line;
                    }
                },
                nullptr);
        if (status != 0) {
            return ScopedAStatus::fromServiceSpecificErrorWithMessage(
                    status, error.empty() ? "probe failed" : error.c_str());
        }
        return ScopedAStatus::ok();
    }

    ScopedAStatus start(const installer::InstallRequest& request,
                        const std::shared_ptr<installer::IProgressCallback>& callback) override {
        if (!CallerAllowed()) return ScopedAStatus::fromExceptionCode(EX_SECURITY);
        if (!callback) return ScopedAStatus::fromExceptionCode(EX_NULL_POINTER);

        std::vector<std::string> args;
        switch (request.mode) {
            case installer::InstallRequest::MODE_DISK:
                args = {"install-disk"};
                for (const auto& size : request.sizes) {
                    if (size.name.empty() ||
                        size.name.find_first_not_of("abcdefghijklmnopqrstuvwxyz_") != std::string::npos ||
                        size.sizeMiB <= 0) {
                        return ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
                    }
                    args.insert(args.end(),
                                {"--size", size.name + "=" + std::to_string(size.sizeMiB)});
                }
                break;
            case installer::InstallRequest::MODE_BESIDE:
                args = {"install-beside", "--userdata-size",
                        std::to_string(request.userdataSizeMiB)};
                break;
            case installer::InstallRequest::MODE_UPGRADE:
                args = {"upgrade"};
                if (request.allowDowngrade) args.push_back("--allow-downgrade");
                break;
            default:
                return ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        if (request.target.empty() || request.target.find('/') != std::string::npos) {
            return ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        if (request.mode != installer::InstallRequest::MODE_UPGRADE) {
            if (request.userdataFs != "ext4" && request.userdataFs != "f2fs") {
                return ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
            }
            args.insert(args.end(), {"--userdata-fs", request.userdataFs});
        }
        args.insert(args.end(), {"--target", request.target});
        if (!request.cmdline.empty()) args.insert(args.end(), {"--cmdline", request.cmdline});
        if (!request.bootEntries) args.push_back("--no-boot-entries");

        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (running_) return IllegalState("An installation is running");
            running_ = true;
            destructive_ = false;
        }
        // Keep running while the installation does, even without clients
        AServiceManager_forceLazyServicesPersist(true);

        std::thread([this, args, callback] {
            std::string error;
            FILE* log = fopen(kLog, "we");
            if (log) {
                fchmod(fileno(log), 0644);
            } else {
                PLOG(ERROR) << "Could not create " << kLog;
            }
            int status = RunScript(
                    args,
                    [&](const std::string& line) {
                        if (log) {
                            fprintf(log, "%s\n", line.c_str());
                            fflush(log);
                        }
                        auto f = Split(line, "\t");
                        if (f[0] == "PROGRESS" && f.size() >= 3) {
                            callback->onProgress(ToInt64(f[1]), f[2]);
                        } else if (f[0] == "STAGE" && f.size() >= 2 && f[1] == "destructive") {
                            {
                                std::lock_guard<std::mutex> lock(mutex_);
                                destructive_ = true;
                            }
                            callback->onDestructive();
                        } else if (f[0] == "ERROR" && f.size() >= 2) {
                            error = f[1];
                        } else {
                            LOG(INFO) << line;
                            callback->onLog(line);
                        }
                    },
                    &pid_, log ? kLog : nullptr);
            if (log) fclose(log);
            if (status != 0 && error.empty()) error = "The installer failed";
            callback->onFinished(status == 0, status == 0 ? "" : error);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                running_ = false;
            }
            AServiceManager_forceLazyServicesPersist(false);
        }).detach();
        return ScopedAStatus::ok();
    }

    ScopedAStatus cancel(bool* result) override {
        if (!CallerAllowed()) return ScopedAStatus::fromExceptionCode(EX_SECURITY);
        std::lock_guard<std::mutex> lock(mutex_);
        *result = running_ && !destructive_ && pid_ > 0;
        if (*result) kill(pid_, SIGTERM);
        return ScopedAStatus::ok();
    }

    ScopedAStatus isRunning(bool* result) override {
        if (!CallerAllowed()) return ScopedAStatus::fromExceptionCode(EX_SECURITY);
        std::lock_guard<std::mutex> lock(mutex_);
        *result = running_;
        return ScopedAStatus::ok();
    }

  private:
    std::mutex mutex_;
    bool running_ = false;
    bool destructive_ = false;
    std::atomic<pid_t> pid_ = -1;
};

}  // namespace

int main() {
    signal(SIGPIPE, SIG_IGN);
    ABinderProcess_setThreadPoolMaxThreadCount(2);
    ABinderProcess_startThreadPool();

    auto service = ndk::SharedRefBase::make<SystemInstaller>();
    binder_status_t status =
            AServiceManager_registerLazyService(service->asBinder().get(), kServiceName);
    CHECK_EQ(status, STATUS_OK) << "Could not register " << kServiceName;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;
}
